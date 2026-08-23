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

    redirect_to replenishments_loss_recoveries_path,
                notice: "Se agregaron #{quantity.to_s('F')} unidad(es) a #{producto.descripcion} (#{variation.description})."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to replenishments_loss_recoveries_path,
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  private

  def load_setting
    @setting = current_business.loss_recovery_setting || current_business.build_loss_recovery_setting
  end

  def loss_recovery_summary
    entries = current_business.loss_recovery_entries
    {
      total_excess_usd: entries.sum(:excess_usd).to_d.round(2),
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
    actor_name = Current.user&.name.to_s.strip
    actor_suffix = actor_name.present? ? " - #{actor_name}" : ''
    "#{REPLENISHMENT_LOT_PREFIX}#{actor_suffix}"
  end
end
