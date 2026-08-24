class LossRecoveriesController < ApplicationController
  REPLENISHMENT_LOT_PREFIX = 'Lote de reposicion por sobrante [RECUPERACION]'.freeze

  before_action :require_business
  before_action :require_admin
  before_action :load_setting

  def index
    @recent_entries = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc).limit(20)
    @summary = loss_recovery_summary
  end

  def history
    scope = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc)

    @from = parse_filter_date(params[:from])
    @to = parse_filter_date(params[:to])

    if @from.present?
      scope = scope.where("occurred_at >= ?", @from.in_time_zone.beginning_of_day)
    end

    if @to.present?
      scope = scope.where("occurred_at <= ?", @to.in_time_zone.end_of_day)
    end

    @entries = scope
    @summary = {
      total_excess_usd: @entries.sum(:excess_usd).to_d.round(2),
      total_base_usd: @entries.sum(:charged_total_usd).to_d.round(2),
      count: @entries.count,
    }
  end

  def update_settings
    attrs = params.require(:loss_recovery_setting).permit(:active, :surcharge_percent, :min_invoice_total_usd)

    attrs[:surcharge_percent] = parse_decimal(attrs[:surcharge_percent]) if attrs.key?(:surcharge_percent)
    attrs[:min_invoice_total_usd] = parse_decimal(attrs[:min_invoice_total_usd]) if attrs.key?(:min_invoice_total_usd)

    @setting.assign_attributes(attrs)
    @setting.active = ActiveModel::Type::Boolean.new.cast(attrs[:active])

    if @setting.save
      redirect_to loss_recoveries_path, notice: "Configuracion de recuperacion actualizada."
    else
      @recent_entries = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc).limit(20)
      @summary = loss_recovery_summary
      render :index, status: :unprocessable_entity
    end
  end

  # GET /recuperacion-perdidas/facturar-perdida
  def new_recovery_invoice
    @query_text = params[:query_text].to_s.strip
    scope = current_business.productos.includes(:product_variations, foto_attachment: :blob).order(Arel.sql('LOWER(productos.descripcion) ASC, productos.id ASC'))
    if @query_text.present?
      terms = @query_text.downcase.split(/\s+/).map(&:strip).reject(&:blank?).uniq
      if terms.any?
        where_clauses = terms.map.with_index { |_, idx| "LOWER(productos.descripcion) LIKE :term#{idx}" }
        bind_values = terms.each_with_index.to_h { |term, idx| ["term#{idx}".to_sym, "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"] }
        scope = scope.where(where_clauses.join(' AND '), bind_values)
      end
    end

    @productos = scope.limit(400)
  end

  # POST /recuperacion-perdidas/facturar-perdida
  def create_recovery_invoice
    items_json = params[:items_json].to_s
    if items_json.blank?
      return redirect_to new_recovery_invoice_loss_recoveries_path, alert: 'No se proporcionaron items para la factura.'
    end

    items = JSON.parse(items_json) rescue nil
    return redirect_to new_recovery_invoice_loss_recoveries_path, alert: 'Formato de items inválido.' if items.blank?

    ActiveRecord::Base.transaction do
      invoice = current_business.recovery_invoices.create!(user: Current.user, occurred_at: Time.current)
      total = 0.to_d

      items.each do |it|
        producto = current_business.productos.find_by(id: it['producto_id'])
        raise ActiveRecord::RecordNotFound, 'Producto no encontrado' unless producto

        variation_id = it['product_variation_id']
        quantity = parse_decimal(it['quantity']).to_d
        unit_price = parse_decimal(it['unit_price_usd']).to_d
        line_total = (quantity * unit_price).round(2)

        # consume inventory with breakdown so we can restore later
        breakdown = producto.consume_variation_stock_with_breakdown!(variation_id: variation_id, quantity_units: quantity) || []

        invoice.recovery_invoice_items.create!(producto: producto, product_variation_id: variation_id, quantity: quantity, unit_price_usd: unit_price, total_price_usd: line_total, lot_breakdown: breakdown)

        total += line_total
      end

      invoice.update!(total_usd: total)
    end

    redirect_to recovery_invoices_loss_recoveries_path, notice: 'Factura de recuperación registrada correctamente.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to new_recovery_invoice_loss_recoveries_path, alert: e.message
  end

  # DELETE /recuperacion-perdidas/facturas-perdida/:id
  def destroy_recovery_invoice
    invoice = current_business.recovery_invoices.find_by(id: params[:id])
    if invoice.blank?
      return redirect_to recovery_invoices_loss_recoveries_path, alert: 'Factura no encontrada.'
    end

    ActiveRecord::Base.transaction do
      # Restore inventory based on lot_breakdown saved in items
      invoice.recovery_invoice_items.each do |item|
        breakdown = item.lot_breakdown || []
        if breakdown.blank?
          raise ActiveRecord::RecordInvalid.new(item), 'No hay información de lotes para restaurar esta línea.'
        end

        breakdown.each do |entry|
          lot = StockLot.find_by(id: entry['stock_lot_id'])
          raise ActiveRecord::RecordNotFound, "Lote #{entry['stock_lot_id']} no encontrado. No se puede restaurar." unless lot

          # find variation row in that lot
          if item.product_variation_id.present?
            row = lot.stock_lot_variations.find_by(product_variation_id: item.product_variation_id)
          else
            row = lot.stock_lot_variations.first
          end

          raise ActiveRecord::RecordNotFound, "No se encuentra la variación en el lote #{lot.id}." unless row

          # add back the consumed quantity
          row.quantity_remaining = row.quantity_remaining.to_d + BigDecimal(entry['quantity'].to_s)
          row.save!

          lot.sync_quantity_remaining_from_variations!
        end
      end

      invoice.destroy!
    end

    redirect_to recovery_invoices_loss_recoveries_path, notice: 'Factura eliminada y stock restaurado correctamente.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to recovery_invoices_loss_recoveries_path, alert: e.message
  end

  # GET /recuperacion-perdidas/facturas-perdida
  def recovery_invoices
    scope = current_business.recovery_invoices.order(occurred_at: :desc)
    @recovery_invoices = scope.limit(500)

    selected_id = params[:invoice_id].to_i
    @selected_recovery_invoice = if selected_id.positive?
                                   current_business
                                     .recovery_invoices
                                     .includes(:user, recovery_invoice_items: %i[producto product_variation])
                                     .find_by(id: selected_id)
                                 end
    @selected_recovery_invoice_items = @selected_recovery_invoice&.recovery_invoice_items&.order(:id) || []
  end

  def replenishments
    @query_text = params[:query_text].to_s.strip

    scope = current_business.productos
                          .includes(:categoria, :product_variations, :stock_lot_variations, foto_attachment: :blob)
                          .order(Arel.sql('LOWER(productos.descripcion) ASC, productos.id ASC'))

    if @query_text.present?
      terms = @query_text.downcase.split(/\s+/).map(&:strip).reject(&:blank?).uniq
      if terms.any?
        where_clauses = terms.map.with_index { |_, idx| "LOWER(productos.descripcion) LIKE :term#{idx}" }
        bind_values = terms.each_with_index.to_h { |term, idx| ["term#{idx}".to_sym, "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"] }
        scope = scope.where(where_clauses.join(' AND '), bind_values)
      end
    end

    @productos = scope.limit(400)
  end

  def create_replenishment
    producto = current_business.productos.find_by(id: replenishment_params[:producto_id])
    return redirect_to replenishments_loss_recoveries_path, alert: 'Producto no encontrado.' if producto.blank?

    variation = producto.product_variations.find_by(id: replenishment_params[:product_variation_id])
    if variation.blank?
      return redirect_to replenishments_loss_recoveries_path,
                         alert: 'Debes seleccionar una variacion valida del producto.'
    end

    quantity = parse_decimal(replenishment_params[:quantity]).to_d.round(3)
    unless quantity.positive?
      return redirect_to replenishments_loss_recoveries_path,
                         alert: 'La cantidad debe ser mayor a cero.'
    end

    occurred_on = parse_filter_date(replenishment_params[:occurred_on]) || Time.current.in_time_zone('America/Caracas').to_date
    default_unit_cost_usd = producto.highest_active_lot_unit_cost_usd.to_d
    unit_cost_usd = default_unit_cost_usd.positive? ? default_unit_cost_usd.round(2) : 0.to_d
    lot_description = build_replenishment_lot_description

    ActiveRecord::Base.transaction do
      lot = producto.stock_lots.create!(
        factura_item_id: nil,
        unit_cost_usd: unit_cost_usd,
        quantity_in: quantity,
        quantity_remaining: quantity,
        purchased_at: occurred_on.in_time_zone('America/Caracas').end_of_day,
        supplier_name: 'Reposicion por sobrante',
        description: lot_description
      )

      lot.stock_lot_variations.create!(
        product_variation_id: variation.id,
        variation_description: variation.description.to_s,
        quantity_in: quantity,
        quantity_remaining: quantity
      )
      lot.sync_quantity_remaining_from_variations!
    end
    respond_to do |format|
      format.html do
        redirect_to replenishments_loss_recoveries_path,
                    notice: "Se agregaron #{quantity.to_s('F')} unidad(es) a #{producto.descripcion} (#{variation.description})."
      end
      format.json do
        render json: { success: true, message: "Se agregaron #{quantity.to_s('F')} unidad(es) a #{producto.descripcion} (#{variation.description}).", lot_id: lot.id, producto_id: producto.id, variation_id: variation.id, quantity: quantity.to_s('F') }, status: :ok
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html do
        redirect_to replenishments_loss_recoveries_path,
                    alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
      end
      format.json do
        render json: { success: false, error: e.record&.errors&.full_messages&.to_sentence.presence || e.message }, status: :unprocessable_entity
      end
    end
  end

  def replenishment_history
    @from = parse_filter_date(params[:from])
    @to = parse_filter_date(params[:to])

    scope = StockLot
            .joins(:producto)
            .includes(:producto, stock_lot_variations: :product_variation)
            .where(productos: { business_id: current_business.id })
            .where("stock_lots.description LIKE ?", "#{REPLENISHMENT_LOT_PREFIX}%")
            .order(purchased_at: :desc, created_at: :desc)

    if @from.present?
      scope = scope.where("stock_lots.purchased_at >= ?", @from.in_time_zone.beginning_of_day)
    end

    if @to.present?
      scope = scope.where("stock_lots.purchased_at <= ?", @to.in_time_zone.end_of_day)
    end

    @replenishment_lots = scope.limit(500)
    @replenishment_summary = {
      count: scope.count,
      quantity_in: scope.sum(:quantity_in).to_d.round(3),
      quantity_remaining: scope.sum(:quantity_remaining).to_d.round(3),
    }
  end

  def destroy_replenishment
    lot = StockLot
          .joins(:producto)
          .where(productos: { business_id: current_business.id })
          .where("stock_lots.description LIKE ?", "#{REPLENISHMENT_LOT_PREFIX}%")
          .find_by(id: params[:id])

    if lot.blank?
      return redirect_to replenishment_history_loss_recoveries_path(history_redirect_params),
                         alert: 'No se encontro el ingreso de reposicion seleccionado.'
    end

    quantity_in = lot.quantity_in.to_d.round(3)
    quantity_remaining = lot.quantity_remaining.to_d.round(3)

    if quantity_remaining < quantity_in
      return redirect_to replenishment_history_loss_recoveries_path(history_redirect_params),
                         alert: 'No se puede revertir este ingreso porque ya se registro una venta donde se vendio una unidad de ese lote.'
    end

    ActiveRecord::Base.transaction do
      lot.destroy!
    end

    redirect_to replenishment_history_loss_recoveries_path(history_redirect_params),
                notice: 'Ingreso de reposicion eliminado y lote revertido correctamente.'
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to replenishment_history_loss_recoveries_path(history_redirect_params),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || 'No se pudo eliminar el ingreso de reposicion.'
  end

  private

  def load_setting
    @setting = current_business.loss_recovery_setting || current_business.build_loss_recovery_setting
  end

  def loss_recovery_summary
    entries = current_business.loss_recovery_entries
    invoices_total = current_business.recovery_invoices.sum(:total_usd).to_d
    total_excess = entries.sum(:excess_usd).to_d - invoices_total
    {
      total_excess_usd: total_excess.round(2),
      total_base_usd: entries.sum(:charged_total_usd).to_d.round(2),
      count: entries.count,
    }
  end

  def parse_filter_date(value)
    return nil if value.blank?

    normalized = value.to_s.strip
    return nil if normalized.blank?

    Date.strptime(normalized, '%Y-%m-%d')
  rescue ArgumentError
    Date.strptime(normalized, '%d-%m-%Y')
  rescue ArgumentError
    nil
  end

  def parse_decimal(value)
    return 0.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/[^\d,.-]/, "")
    if cleaned.include?(",") && cleaned.include?(".")
      cleaned = cleaned.gsub(".", "").tr(",", ".")
    elsif cleaned.include?(",")
      cleaned = cleaned.tr(",", ".")
    end

    BigDecimal(cleaned)
  rescue ArgumentError
    0.to_d
  end

  def replenishment_params
    params.permit(:producto_id, :product_variation_id, :quantity, :occurred_on)
  end

  def build_replenishment_lot_description
    actor_name = Current.user&.display_name.to_s.strip
    actor_name = Current.user&.full_name.to_s.strip if actor_name.blank?
    actor_name = Current.user&.username.to_s.strip if actor_name.blank?
    actor_name = Current.user&.email.to_s.strip if actor_name.blank?
    actor_suffix = actor_name.present? ? " - #{actor_name}" : ''
    "#{REPLENISHMENT_LOT_PREFIX}#{actor_suffix}"
  end

  def history_redirect_params
    params.permit(:from, :to).to_h
  end
end
