class PurchaseInvoicesController < ApplicationController
  PER_PAGE = 15
  INITIAL_INVENTORY_TEMPLATE_HEADERS = [
    'producto_id',
    'producto',
    'variacion_id',
    'variacion',
    'costo_unit_usd',
    'existencia_inicial',
    'exento'
  ].freeze
  INVOICE_PAYMENT_STATUS_LABELS = {
    'paid' => 'Pagada',
    'partial' => 'Parcialmente pagada',
    'due' => 'Se debe'
  }.freeze
  INVOICE_PAYMENT_STATUS_BADGE_CLASSES = {
    'paid' => 'border-emerald-200 bg-emerald-50 text-emerald-700',
    'partial' => 'border-amber-200 bg-amber-50 text-amber-700',
    'due' => 'border-rose-200 bg-rose-50 text-rose-700'
  }.freeze

  helper_method :invoice_payment_status_filter_options,
                :invoice_payment_status_for,
                :invoice_payment_status_label,
                :invoice_payment_status_badge_class

  before_action :require_business
  before_action :require_admin
  before_action :ensure_purchase_invoice_columns_loaded
  before_action :set_purchase_invoice, only: %i[show edit update destroy]
  before_action :load_suppliers, only: %i[index new edit create update]
  before_action :load_bs_accounts, only: %i[new create]
  before_action :load_intercompany_options, only: %i[new create edit update]
  before_action :load_invoice_payment_summary, only: %i[show edit]

  def index
    base_scope = current_business.purchase_invoices.includes(:supplier)

    @initial_inventory_invoice = current_business.purchase_invoices.initial_inventory.order(created_at: :desc).first
    @hide_initial_inventory_button = current_business.hide_initial_inventory_button?

    @has_purchase_invoices = base_scope.exists?
    @selected_supplier_id = params[:supplier_id].to_s.strip.presence
    @selected_payment_status = normalize_invoice_payment_status(params[:payment_status])
    @fecha_desde = parse_filter_date(params[:fecha_desde])
    @fecha_hasta = parse_filter_date(params[:fecha_hasta])

    if @fecha_desde.present? && @fecha_hasta.present? && @fecha_desde > @fecha_hasta
      @fecha_desde, @fecha_hasta = @fecha_hasta, @fecha_desde
    end

    @fecha_desde_value = normalized_filter_date_value(params[:fecha_desde], @fecha_desde)
    @fecha_hasta_value = normalized_filter_date_value(params[:fecha_hasta], @fecha_hasta)
    @filters_applied = [
      @selected_supplier_id,
      @selected_payment_status,
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip
    ].any?(&:present?)

    base_scope = base_scope.where(supplier_id: @selected_supplier_id) if @selected_supplier_id.present?

    base_scope = base_scope.where('facturas.fecha_emision >= ?', @fecha_desde.beginning_of_day) if @fecha_desde.present?
    base_scope = base_scope.where('facturas.fecha_emision <= ?', @fecha_hasta.end_of_day) if @fecha_hasta.present?

    ordered_invoices = base_scope.order(fecha_emision: :desc, created_at: :desc).to_a
    full_status_map = build_invoice_payment_status_map(ordered_invoices)

    if @selected_payment_status.present?
      ordered_invoices = ordered_invoices.select do |invoice|
        full_status_map[invoice.id] == @selected_payment_status
      end
    end

    @matching_purchase_invoices_count = ordered_invoices.size
    @page = params[:page].to_i
    @page = 1 if @page < 1

    invoices = ordered_invoices.drop(page_offset).first(PER_PAGE + 1)
    @next_page = invoices.length > PER_PAGE ? @page + 1 : nil
    @purchase_invoices = invoices.first(PER_PAGE)
    @invoice_payment_status_map = full_status_map.slice(*@purchase_invoices.map(&:id))

    render json: paginated_purchase_invoices_payload if request.format.json?
  end

  def initial_inventory
    invoice = current_business.purchase_invoices.initial_inventory.order(created_at: :desc).first

    if invoice.present?
      redirect_to edit_purchase_invoice_path(invoice)
    else
      redirect_to new_purchase_invoice_path(invoice_kind: PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY)
    end
  end

  def initial_inventory_template
    rows = [INITIAL_INVENTORY_TEMPLATE_HEADERS]

    current_business.productos
            .includes(:product_variations)
            .order(Arel.sql('LOWER(productos.descripcion) ASC'), :id)
            .each do |producto|
      variations = producto.product_variations.order(:id).to_a
      unit_cost = producto.highest_active_lot_unit_cost_usd.to_d
      unit_cost = producto.precio_venta_usd.to_d if unit_cost <= 0
      exento = producto.respond_to?(:exento?) && producto.exento? ? 'si' : 'no'

      if variations.any?
        variations.each do |variation|
          rows << [
            producto.id,
            producto.descripcion,
            variation.id,
            variation.description,
            unit_cost.to_s('F'),
            '0',
            exento
          ]
        end
      else
        rows << [
          producto.id,
          producto.descripcion,
          '',
          'Unica',
          unit_cost.to_s('F'),
          '0',
          exento
        ]
      end
    end

    csv_body = rows.map { |row| build_csv_row(row) }.join("\n")
    filename = "plantilla_inventario_inicial_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"

    send_data "\uFEFF#{csv_body}",
              filename: filename,
              type: 'text/csv; charset=utf-8',
              disposition: 'attachment'
  end

  def source_business_accounts
    source_id = params[:source_business_id].to_s.strip.to_i
    return render json: [] if source_id <= 0
    return render json: [] if current_business.present? && source_id == current_business.id

    source_business = Business.find_by(id: source_id)
    return render json: [] if source_business.blank?

    accounts = source_business.accounts
                  .where(account_type: 'bank_account', currency: 'VES')
                              .order(:name)
                              .map do |account|
      account_name = account.name.to_s.strip
      next if account_name.blank?

      {
        id: account.id,
        name: account_name,
        balance: account.balance.to_d,
        currency: account.currency,
        active: account.active
      }
    end.compact

    render json: accounts
  end

  def import_initial_inventory
    file = params[:inventory_file]
    if file.blank?
      redirect_to purchase_invoices_path,
                  alert: 'Debes seleccionar un archivo de plantilla para importar inventario inicial.'
      return
    end

    parsed_rows = parse_inventory_template(file: file)
    if parsed_rows.empty?
      redirect_to purchase_invoices_path,
                  alert: 'La plantilla no contiene filas válidas para importar.'
      return
    end

    grouped_rows = parsed_rows.group_by { |row| row[:producto_id] }
    product_ids = grouped_rows.keys
    products_by_id = current_business.productos.includes(:product_variations).where(id: product_ids).index_by(&:id)

    missing_ids = product_ids - products_by_id.keys
    if missing_ids.any?
      redirect_to purchase_invoices_path,
                  alert: "Hay productos que no existen en este negocio: #{missing_ids.join(', ')}"
      return
    end

    item_attributes = []
    grouped_rows.each do |producto_id, rows|
      producto = products_by_id[producto_id]
      variations_by_id = producto.product_variations.index_by(&:id)

      costs = rows.map { |row| row[:costo_unit_usd] }.uniq
      if costs.size > 1
        redirect_to purchase_invoices_path,
                    alert: "El producto ##{producto_id} tiene costos unitarios distintos en la plantilla."
        return
      end

      exento_values = rows.map { |row| row[:exento] }.uniq
      if exento_values.size > 1
        redirect_to purchase_invoices_path,
                    alert: "El producto ##{producto_id} tiene valores de exento distintos en la plantilla."
        return
      end

      variation_breakdown = rows.filter_map do |row|
        next if row[:existencia_inicial] <= 0

        variation_id = row[:variacion_id]
        variation_name = row[:variacion].presence

        if variation_id.present?
          variation = variations_by_id[variation_id]
          unless variation
            redirect_to purchase_invoices_path,
                        alert: "La variación ##{variation_id} no pertenece al producto ##{producto_id}."
            return
          end
          variation_name = variation.description
        end

        {
          'variation_id' => variation_id,
          'description' => variation_name.presence || 'Variación',
          'quantity' => row[:existencia_inicial].to_f
        }
      end

      total_quantity = variation_breakdown.sum { |entry| entry['quantity'].to_d }
      next if total_quantity <= 0

      item_attributes << {
        producto_id: producto.id,
        product_name: producto.descripcion,
        costo_mayor: costs.first.to_d,
        unid_x_pack: 1,
        cantidad: total_quantity,
        exento: exento_values.first,
        variation_breakdown: variation_breakdown
      }
    end

    if item_attributes.empty?
      redirect_to purchase_invoices_path,
                  alert: 'No se detectaron existencias iniciales mayores a cero para importar.'
      return
    end

    PurchaseInvoice.transaction do
      invoice = current_business.purchase_invoices.initial_inventory.order(created_at: :desc).first
      invoice ||= current_business.purchase_invoices.new

      invoice.assign_attributes(
        invoice_kind: PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY,
        supplier_id: nil,
        supplier_name: nil,
        fecha_emision: Time.current.in_time_zone('America/Caracas').to_date,
        tasa_dolar: TasaCambio.latest_value('Dolar BCV').to_d
      )

      invoice.save! if invoice.new_record?
      invoice.purchase_invoice_items.destroy_all
      item_attributes.each { |attrs| invoice.purchase_invoice_items.create!(attrs) }
      invoice.save!
    end

    redirect_to initial_inventory_purchase_invoices_path,
                notice: "Inventario inicial importado correctamente (#{item_attributes.size} productos actualizados)."
  rescue StandardError => e
    redirect_to purchase_invoices_path,
                alert: "No se pudo importar la plantilla: #{e.message}"
  end

  def show
    @highlight_from_lot = params[:source].to_s == 'lot'
    @highlighted_item_id = if @highlight_from_lot && params[:highlighted_item_id].present?
                             parsed_id = params[:highlighted_item_id].to_i
                             parsed_id.positive? ? parsed_id : nil
                           end
  end

  def new
    if initial_inventory_mode_requested?
      existing_initial_inventory = current_business.purchase_invoices.initial_inventory.order(created_at: :desc).first
      if existing_initial_inventory.present?
        redirect_to edit_purchase_invoice_path(existing_initial_inventory),
                    alert: 'Ya existe un inventario inicial para este negocio. Puedes editarlo.'
        return
      end
    end

    caracas_now = Time.current.in_time_zone('America/Caracas')
    tasa_hoy_bcv = TasaCambio.find_by(description: 'Dolar BCV', fecha_referencia: caracas_now.to_date)&.valor

    @purchase_invoice = current_business.purchase_invoices.new(
      fecha_emision: caracas_now.to_date,
      tasa_dolar: tasa_hoy_bcv
    )
    @purchase_invoice.invoice_kind = requested_invoice_kind
    @purchase_invoice.intercompany = intercompany_mode_requested?
    if intercompany_mode_requested?
      @purchase_invoice.source_business_id = requested_source_business_id
      if @purchase_invoice.source_business_id.blank?
        preferred_source_business = @available_source_businesses.detect { |business| business.productos.exists? } || @available_source_businesses.first
        @purchase_invoice.source_business_id = preferred_source_business&.id
      end
    end
    apply_invoice_payment_form_state(default_invoice_payment_context) unless @purchase_invoice.initial_inventory?
    # render view with turbo_frame_tag so the response includes the expected frame
    # the corresponding template (new.html.erb) already wraps content in
    # <turbo-frame id="modal-facturas">...
    render :new
  end

  def create
    payment_context = nil
    @purchase_invoice = current_business.purchase_invoices.new(purchase_invoice_params)
    @purchase_invoice.invoice_kind = requested_invoice_kind
    source_business = intercompany_mode_requested? ? intercompany_source_business : nil

    if @purchase_invoice.initial_inventory?
      if @purchase_invoice.save
        redirect_to purchase_invoices_path, notice: 'Inventario inicial registrado correctamente'
      else
        render :new, status: :unprocessable_entity
      end
      return
    end

    @purchase_invoice.valid?
    payment_context = build_invoice_payment_context(@purchase_invoice, source_business: source_business)

    if intercompany_mode_requested?
      if source_business.blank?
        @purchase_invoice.errors.add(:source_business_id, 'debe seleccionar un negocio origen válido.')
      end
    end

    if @purchase_invoice.errors.any?
      apply_invoice_payment_form_state(payment_context)
      render :new, status: :unprocessable_entity
      return
    end

    if intercompany_mode_requested?
      result = Intercompany::PurchaseInvoiceCreator.new(
        current_business: current_business,
        source_business: source_business,
        purchase_invoice: @purchase_invoice,
        payment_context: payment_context,
        current_user: Current.user
      ).call

      unless result.success?
        Array(result.errors).each { |message| @purchase_invoice.errors.add(:base, message) }
        apply_invoice_payment_form_state(payment_context)
        render :new, status: :unprocessable_entity
        return
      end
    else
      PurchaseInvoice.transaction do
        @purchase_invoice.save!
        create_invoice_payment_movements!(@purchase_invoice, payment_context[:payments])
        create_pending_supplier_debt!(@purchase_invoice, payment_context)
      end
    end

    redirect_to purchase_invoices_path, notice: 'Factura creada correctamente'
  rescue ActiveRecord::RecordInvalid => e
    if e.record&.respond_to?(:errors) && e.record.errors.any?
      e.record.errors.full_messages.each { |message| @purchase_invoice.errors.add(:base, message) }
    else
      @purchase_invoice.errors.add(:base, e.message)
    end

    apply_invoice_payment_form_state(payment_context || default_invoice_payment_context)
    render :new, status: :unprocessable_entity
  end

  def edit
    @purchase_invoice.purchase_invoice_items.build if @purchase_invoice.purchase_invoice_items.empty?
  end

  def update
    return update_intercompany_invoice if @purchase_invoice.intercompany?

    if @purchase_invoice.update(purchase_invoice_params)
      success_message = if @purchase_invoice.initial_inventory?
                          'Inventario inicial actualizado'
                        else
                          'Factura actualizada'
                        end

      redirect_to purchase_invoices_path, notice: success_message
    else
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
    end
  end

  def update_intercompany_invoice
    source_business = @purchase_invoice.source_business
    payment_context = nil
    if source_business.blank?
      @purchase_invoice.errors.add(:base, 'La factura interempresa no tiene negocio origen válido.')
      apply_invoice_payment_form_state(default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    prior_rows = aggregate_source_stock_rows_for_invoice_items(
      @purchase_invoice.purchase_invoice_items.includes(producto: :product_variations),
      source_business: source_business,
    )

    if @purchase_invoice.errors.any?
      apply_invoice_payment_form_state(default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    PurchaseInvoice.transaction do
      restore_source_stock_rows!(rows: prior_rows)
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      @purchase_invoice.assign_attributes(purchase_invoice_params)
      normalize_intercompany_items_for_destination!(@purchase_invoice, source_business: source_business)
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      payment_context = build_invoice_payment_context(@purchase_invoice, source_business: source_business)
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      @purchase_invoice.save!

      current_rows = aggregate_source_stock_rows_for_invoice_items(
        @purchase_invoice.purchase_invoice_items.includes(producto: :product_variations),
        source_business: source_business,
      )
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      consume_source_stock_rows!(rows: current_rows)
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      sync_intercompany_payment_movements!(
        @purchase_invoice,
        payments: payment_context[:payments],
        source_business: source_business,
      )
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?

      sync_intercompany_pending_debts!(@purchase_invoice, source_business: source_business)
      raise ActiveRecord::Rollback if @purchase_invoice.errors.any?
    end

    if @purchase_invoice.errors.any?
      apply_invoice_payment_form_state(payment_context || default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    success_message = if @purchase_invoice.initial_inventory?
                        'Inventario inicial actualizado'
                      else
                        'Factura actualizada'
                      end

    redirect_to purchase_invoices_path, notice: success_message
  rescue ActiveRecord::RecordInvalid => e
    if e.record&.respond_to?(:errors) && e.record.errors.any?
      e.record.errors.full_messages.each { |message| @purchase_invoice.errors.add(:base, message) }
    else
      @purchase_invoice.errors.add(:base, e.message)
    end

    apply_invoice_payment_form_state(payment_context || default_invoice_payment_context)
    load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
    render :edit, status: :unprocessable_entity
  end

  def destroy
    PurchaseInvoice.transaction do
      remove_invoice_related_records!(@purchase_invoice)
      @purchase_invoice.destroy!
    end

    redirect_to purchase_invoices_path,
                notice: destroy_notice_message(@purchase_invoice)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to purchase_invoices_path, alert: e.message.presence || 'No se pudo eliminar la factura.'
  end

  private

  def parse_inventory_template(file:)
    raw = file.read
    text = raw.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    text = text.delete_prefix("\uFEFF")
    lines = text.split(/\r\n|\n|\r/).reject { |line| line.strip.empty? }
    return [] if lines.empty?

    delimiter = detect_template_delimiter(lines.first)
    headers = split_template_row(lines.shift, delimiter: delimiter).map { |header| normalize_template_header(header) }
    header_index = headers.each_with_index.to_h

    required_headers = %w[producto_id costo_unit_usd existencia_inicial exento]
    missing_headers = required_headers - header_index.keys
    raise "La plantilla no contiene columnas requeridas: #{missing_headers.join(', ')}" if missing_headers.any?

    rows = []
    lines.each_with_index do |line, index|
      row_number = index + 2
      values = split_template_row(line, delimiter: delimiter)
      producto_id_raw = values[header_index['producto_id']].to_s.strip
      next if producto_id_raw.blank?

      unless producto_id_raw.match?(/\A\d+\z/)
        raise "Fila #{row_number}: producto_id invalido"
      end

      producto_id = producto_id_raw.to_i

      costo_unit = parse_template_decimal(
        values[header_index['costo_unit_usd']],
        field_name: 'costo_unit_usd',
        row_number: row_number
      )
      existencia = parse_template_decimal(
        values[header_index['existencia_inicial']],
        field_name: 'existencia_inicial',
        row_number: row_number
      )

      if costo_unit.negative?
        raise "Fila #{row_number}: costo_unit_usd no puede ser negativo"
      end

      if existencia.negative?
        raise "Fila #{row_number}: existencia_inicial no puede ser negativa"
      end

      variacion_id_idx = header_index['variacion_id']
      variacion_idx = header_index['variacion']
      exento_raw = values[header_index['exento']]
      variacion_id_raw = variacion_id_idx ? values[variacion_id_idx].to_s.strip : ''
      variacion_id = variacion_id_raw.match?(/\A\d+\z/) ? variacion_id_raw.to_i : nil

      rows << {
        producto_id: producto_id,
        variacion_id: variacion_id,
        variacion: variacion_idx ? values[variacion_idx].to_s.strip : nil,
        costo_unit_usd: costo_unit,
        existencia_inicial: existencia,
        exento: parse_template_boolean(exento_raw)
      }
    end

    rows
  end

  def detect_template_delimiter(header_line)
    candidates = [';', ',', "\t"]
    candidates.max_by { |delimiter| header_line.count(delimiter) }
  end

  def split_template_row(line, delimiter:)
    values = []
    current = +''
    in_quotes = false
    chars = line.to_s.chars
    i = 0

    while i < chars.length
      char = chars[i]
      if char == '"'
        if in_quotes && chars[i + 1] == '"'
          current << '"'
          i += 1
        else
          in_quotes = !in_quotes
        end
      elsif char == delimiter && !in_quotes
        values << current
        current = +''
      else
        current << char
      end
      i += 1
    end

    values << current
    values.map(&:strip)
  end

  def normalize_template_header(value)
    value.to_s.strip.downcase
         .tr('áéíóúüñ', 'aeiouun')
         .gsub(/\s+/, '_')
  end

  def parse_template_decimal(value, field_name:, row_number:)
    raw = value.to_s.strip
    return 0.to_d if raw.blank?

    normalized = raw.gsub(/\./, '').tr(',', '.') if raw.include?(',') && raw.include?('.')
    normalized ||= raw.tr(',', '.')
    BigDecimal(normalized)
  rescue ArgumentError
    raise "Fila #{row_number}: #{field_name} invalido"
  end

  def parse_template_boolean(value)
    normalized = value.to_s.strip.downcase
    %w[1 true t si s yes y].include?(normalized)
  end

  def build_csv_row(fields)
    fields.map { |field| csv_escape(field) }.join(';')
  end

  def csv_escape(value)
    raw = value.to_s
    escaped = raw.gsub('"', '""')
    return escaped unless escaped.match?(/[";\n\r]/)

    "\"#{escaped}\""
  end

  def ensure_purchase_invoice_columns_loaded
    return if PurchaseInvoice.attribute_names.include?('invoice_kind')

    PurchaseInvoice.reset_column_information
  end

  def set_purchase_invoice
    @purchase_invoice = current_business.purchase_invoices.find(params[:id])
  end

  def load_suppliers
    @available_suppliers = current_business.suppliers.order(:nombre)
  end

  def load_intercompany_options
    @available_source_businesses = if Current.user&.admin?
                                     Business.where.not(id: current_business&.id).order(:name)
                                   else
                                     Business.none
                                   end

    @source_accounts_map = @available_source_businesses.each_with_object({}) do |business, hash|
      hash[business.id] = business.accounts
              .where(account_type: 'bank_account', currency: 'VES')
                              .order(:name)
                              .map do |account|
        {
          id: account.id,
          name: account.name,
          balance: account.balance.to_d,
          currency: account.currency,
          active: account.active
        }
      end
    end
  end

  def load_bs_accounts
    @bs_accounts = current_business.accounts.where(active: true, currency: 'VES').order(:name)
  end

  def purchase_invoice_params
    params.require(:purchase_invoice).permit(
      :supplier_id,
      :intercompany,
      :source_business_id,
      :fecha_emision,
      :tasa_dolar,
      :numero,
      :observaciones,
      purchase_invoice_items_attributes: %i[
        id
        producto_id
        product_name
        costo_mayor
        costo_mayor_bs
        cantidad
        costo_menor
        unid_x_pack
        subtotal
        exento
        variation_breakdown
        _destroy
      ]
    )
  end

  def intercompany_mode_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:purchase_invoice, :intercompany)) || params[:mode].to_s == 'intercompany'
  end

  def requested_source_business_id
    raw = params.dig(:purchase_invoice, :source_business_id).to_s.strip
    return nil if raw.blank?

    raw.to_i
  end

  def intercompany_source_business
    source_id = requested_source_business_id
    return nil if source_id.blank?

    scope = if Current.user&.admin?
              Business.all
            elsif Current.user&.business_id.present?
              Business.where(id: Current.user.business_id)
            else
              Business.none
            end

    scope.where.not(id: current_business.id).find_by(id: source_id)
  end

  def requested_invoice_kind
    raw_kind = params[:invoice_kind].presence || params.dig(:purchase_invoice, :invoice_kind)
    raw_kind = raw_kind.to_s.strip
    if raw_kind == PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY
      return PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY
    end

    PurchaseInvoice::INVOICE_KIND_PURCHASE
  end

  def initial_inventory_mode_requested?
    requested_invoice_kind == PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY
  end

  def destroy_notice_message(invoice)
    if invoice.initial_inventory?
      'Inventario inicial eliminado correctamente. Se revirtieron lotes asociados.'
    else
      'Factura eliminada correctamente. Se revirtieron pagos, deudas y lotes asociados.'
    end
  end

  def default_invoice_payment_context
    {
      rows: [default_invoice_payment_row],
      mark_pending_payment: false,
      pending_due_on: nil,
      pending_due_on_value: ''
    }
  end

  def default_invoice_payment_row
    { account_id: '', source_account_id: '', amount: '' }
  end

  def apply_invoice_payment_form_state(context)
    @invoice_payment_rows = context[:rows].presence || [default_invoice_payment_row]
    @pending_payment_checked = context[:mark_pending_payment] == true
    @pending_due_on_value = context[:pending_due_on_value].to_s
  end

  def build_invoice_payment_context(invoice, source_business: nil)
    rows_for_form = invoice_payment_rows_for_form
    normalized_rows = normalize_invoice_payment_rows(rows_for_form)
    mark_pending_payment = ActiveModel::Type::Boolean.new.cast(params[:mark_pending_payment])
    pending_due_on_raw = params[:pending_due_on].to_s.strip
    pending_due_on = parse_filter_date(pending_due_on_raw)

    payments = build_invoice_payment_records(invoice, normalized_rows, source_business: source_business)

    total_invoice_bs = invoice.total_bs.to_d.round(2)
    total_paid_bs = payments.sum { |entry| entry[:amount].to_d }.round(2)
    pending_amount_bs = (total_invoice_bs - total_paid_bs).round(2)
    pending_amount_bs = 0.to_d if pending_amount_bs.abs < 0.01.to_d

    if !mark_pending_payment && payments.empty?
      invoice.errors.add(:base, 'Debes registrar al menos un pago en Bs o marcar la factura como pendiente por pagar.')
    end

    if total_paid_bs > (total_invoice_bs + 0.01.to_d)
      invoice.errors.add(:base, 'El total pagado en Bs no puede exceder el total de la factura.')
    end

    if pending_amount_bs.positive? && !mark_pending_payment
      invoice.errors.add(:base,
                         'El pago no cubre el total de la factura. Marca la opción pendiente por pagar para guardar el saldo.')
    end

    if mark_pending_payment && pending_amount_bs.positive? && pending_due_on.blank?
      invoice.errors.add(:base, 'Debes indicar la fecha de vencimiento para el saldo pendiente.')
    end

    insufficient_messages = insufficient_payment_balance_messages(payments)
    if insufficient_messages.any?
      invoice.errors.add(:base, "Cuentas con saldo insuficiente: #{insufficient_messages.join(' ')}")
    end

    {
      rows: rows_for_form,
      mark_pending_payment: mark_pending_payment,
      pending_due_on: pending_due_on,
      pending_due_on_value: normalized_filter_date_value(pending_due_on_raw, pending_due_on),
      payments: payments,
      total_invoice_bs: total_invoice_bs,
      total_paid_bs: total_paid_bs,
      pending_amount_bs: [pending_amount_bs, 0.to_d].max
    }
  end

  def build_invoice_payment_records(invoice, normalized_rows, source_business: nil)
    account_ids = normalized_rows.map { |row| row[:account_id].to_i }.select(&:positive?).uniq
    accounts_by_id = current_business.accounts.where(id: account_ids).index_by(&:id)
    source_accounts_by_id = if invoice.intercompany? && source_business.present?
                              source_account_ids = normalized_rows.map { |row| row[:source_account_id].to_i }.select(&:positive?).uniq
                              source_business.accounts.where(id: source_account_ids, account_type: 'bank_account', currency: 'VES').index_by(&:id)
                            else
                              {}
                            end

    normalized_rows.each_with_index.filter_map do |row, index|
      row_number = index + 1

      if row[:account_id].blank?
        invoice.errors.add(:base, "Pago #{row_number}: selecciona una cuenta en Bs.")
        next
      end

      amount = row[:amount].to_d.round(2)
      if amount <= 0
        invoice.errors.add(:base, "Pago #{row_number}: el monto debe ser mayor a cero.")
        next
      end

      account = accounts_by_id[row[:account_id].to_i]
      if account.blank?
        invoice.errors.add(:base, "Pago #{row_number}: la cuenta seleccionada no es válida.")
        next
      end

      if account.currency != 'VES'
        invoice.errors.add(:base, "Pago #{row_number}: la cuenta #{account.name} no está en Bs.")
        next
      end

      source_account = nil
      if invoice.intercompany?
        if source_business.blank?
          invoice.errors.add(:base, "Pago #{row_number}: selecciona primero un negocio origen válido.")
          next
        end

        if row[:source_account_id].blank?
          invoice.errors.add(:base, "Pago #{row_number}: selecciona la cuenta a acreditar en negocio origen.")
          next
        end

        source_account = source_accounts_by_id[row[:source_account_id].to_i]
        if source_account.blank?
          invoice.errors.add(:base, "Pago #{row_number}: la cuenta a acreditar en origen no es válida.")
          next
        end
      end

      { account: account, source_account: source_account, amount: amount }
    end
  end

  def insufficient_payment_balance_messages(payments)
    grouped_amounts = payments.group_by { |entry| entry[:account].id }

    grouped_amounts.each_with_object([]) do |(_account_id, entries), messages|
      account = entries.first[:account]
      required_amount = entries.sum { |entry| entry[:amount].to_d }.round(2)

      next if required_amount <= (account.balance.to_d + 0.01.to_d)

      messages << account.insufficient_balance_message(required_amount, available_balance: account.balance)
    end
  end

  def create_invoice_payment_movements!(invoice, payments)
    occurred_at = invoice.fecha_emision.presence || Time.current
    description = build_invoice_payment_movement_description(invoice)

    payments.each do |entry|
      movement_attrs = {
        movement_kind: 'expense',
        amount: entry[:amount],
        description: description,
        occurred_at: occurred_at
      }

      movement_attrs[:payment_method] = 'transfer' if entry[:account].account_type == 'bank_account'

      entry[:account].account_movements.create!(movement_attrs)
    end
  end

  def create_pending_supplier_debt!(invoice, payment_context)
    pending_amount_bs = payment_context[:pending_amount_bs].to_d.round(2)
    return unless pending_amount_bs.positive?

    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    supplier_name = invoice.supplier_display_name

    current_business.debts.create!(
      debt_kind: 'payable',
      name: supplier_name,
      description: "Saldo pendiente factura #{invoice_reference} - Proveedor: #{supplier_name} [FACTURA_COMPRA:#{invoice.id}]",
      amount: pending_amount_bs,
      currency: 'VES',
      issued_on: invoice.fecha_emision&.to_date || Date.current,
      due_on: payment_context[:pending_due_on]
    )
  end

  def build_invoice_payment_movement_description(invoice)
    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    "Pago factura compra #{invoice_reference} - #{invoice.supplier_display_name} [FACTURA_COMPRA:#{invoice.id}]"
  end

  def invoice_payment_rows_for_form
    rows = raw_invoice_payment_rows.map do |row|
      {
        account_id: row_value(row, :account_id).to_s.strip,
        source_account_id: row_value(row, :source_account_id).to_s.strip,
        amount: row_value(row, :amount).to_s.strip
      }
    end

    rows = rows.reject { |row| row[:account_id].blank? && row[:amount].blank? }
    rows.presence || [default_invoice_payment_row]
  end

  def normalize_invoice_payment_rows(rows)
    rows.filter_map do |row|
      account_id = row[:account_id].to_s.strip
      amount = parse_decimal(row[:amount])
      next if account_id.blank? && amount <= 0

      {
        account_id: account_id,
        source_account_id: row[:source_account_id].to_s.strip,
        amount: amount
      }
    end
  end

  def raw_invoice_payment_rows
    raw = params[:invoice_payments]

    case raw
    when ActionController::Parameters
      raw.to_unsafe_h.sort_by { |key, _| key.to_i }.map { |_key, value| value }
    when Hash
      raw.sort_by { |key, _| key.to_i }.map { |_key, value| value }
    when Array
      raw
    else
      []
    end
  end

  def row_value(row, key)
    return '' if row.blank?

    row_hash = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
    row_hash[key].presence || row_hash[key.to_s].presence || ''
  end

  def parse_decimal(value)
    return 0.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/[^\d,.-]/, '')
    if cleaned.include?(',') && cleaned.include?('.')
      cleaned = cleaned.gsub('.', '').tr(',', '.')
    elsif cleaned.include?(',')
      cleaned = cleaned.tr(',', '.')
    end

    BigDecimal(cleaned)
  rescue ArgumentError
    0.to_d
  end

  def parse_filter_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    return Date.strptime(raw.tr('/', '-'), '%d-%m-%Y') if raw.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(raw) if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(raw)
  rescue ArgumentError
    nil
  end

  def normalized_filter_date_value(raw_value, parsed_value)
    return parsed_value.strftime('%d-%m-%Y') if parsed_value.present?

    raw_value.to_s.strip
  end

  def normalize_invoice_payment_status(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    INVOICE_PAYMENT_STATUS_LABELS.key?(value) ? value : nil
  end

  def invoice_payment_status_filter_options
    [['Todos los estados', '']] + INVOICE_PAYMENT_STATUS_LABELS.map { |key, label| [label, key] }
  end

  def invoice_payment_status_for(invoice)
    @invoice_payment_status_map&.fetch(invoice.id, nil) || 'due'
  end

  def invoice_payment_status_label(status_key)
    INVOICE_PAYMENT_STATUS_LABELS[status_key.to_s] || INVOICE_PAYMENT_STATUS_LABELS['due']
  end

  def invoice_payment_status_badge_class(status_key)
    INVOICE_PAYMENT_STATUS_BADGE_CLASSES[status_key.to_s] || INVOICE_PAYMENT_STATUS_BADGE_CLASSES['due']
  end

  def build_invoice_payment_status_map(invoices)
    invoices.each_with_object({}) do |invoice, map|
      if invoice.initial_inventory?
        map[invoice.id] = 'paid'
        next
      end

      total_paid_bs = invoice_payment_movements_scope(invoice).sum(:amount).to_d.round(2)
      pending_debt = find_invoice_pending_debt(invoice)
      pending_balance_bs = pending_debt&.balance.to_d.round(2)

      map[invoice.id] = if pending_balance_bs.positive?
                          total_paid_bs.positive? ? 'partial' : 'due'
                        elsif total_paid_bs.positive? || pending_debt.present?
                          'paid'
                        else
                          'due'
                        end
    end
  end

  def page_offset
    (@page - 1) * PER_PAGE
  end

  def paginated_purchase_invoices_payload
    {
      mobile_html: purchase_invoice_cards_html,
      table_rows_html: purchase_invoice_rows_html,
      next_page: @next_page,
      batch_count: @purchase_invoices.size
    }
  end

  def purchase_invoice_cards_html
    @purchase_invoices.map do |purchase_invoice|
      render_to_string(
        partial: 'purchase_invoices/purchase_invoice_card',
        formats: [:html],
        locals: { purchase_invoice: purchase_invoice }
      )
    end.join
  end

  def purchase_invoice_rows_html
    @purchase_invoices.each_with_index.map do |purchase_invoice, index|
      render_to_string(
        partial: 'purchase_invoices/purchase_invoice_row',
        formats: [:html],
        locals: { purchase_invoice: purchase_invoice, index: page_offset + index }
      )
    end.join
  end

  def load_invoice_payment_summary
    @invoice_payment_movements = invoice_payment_movements_scope(@purchase_invoice)
    @invoice_pending_debt = find_invoice_pending_debt(@purchase_invoice)
    @invoice_bcv_rate = invoice_bcv_rate_for_today
    @invoice_pending_balance_bs = [@invoice_pending_debt&.balance.to_d.round(2), 0.to_d].max
    @invoice_debt_assigned_bs = @invoice_pending_debt&.amount.to_d.round(2)
    @invoice_total_paid_bs = [@purchase_invoice.total_bs.to_d - @invoice_pending_balance_bs, 0.to_d].max.round(2)
  end

  def invoice_bcv_rate_for_today
    caracas_today = Time.current.in_time_zone('America/Caracas').to_date
    rate = CurrencyConverter.rate_to_ves('USD', on_date: caracas_today).to_d

    return rate.round(4) if rate.positive?

    @purchase_invoice.tasa_dolar.to_d.round(4)
  end

  def invoice_payment_movements_scope(invoice)
    AccountMovement.joins(:account)
                   .includes(:account)
                   .where(accounts: { business_id: current_business.id })
                   .where('account_movements.description LIKE ?', "%[FACTURA_COMPRA:#{invoice.id}]%")
                   .order(occurred_at: :desc, created_at: :desc)
  end

  def source_invoice_payment_movements_scope(invoice)
    return AccountMovement.none if invoice.source_business_id.blank?

    AccountMovement.joins(:account)
                   .includes(:account)
                   .where(accounts: { business_id: invoice.source_business_id })
                   .where('account_movements.description LIKE ?', "%[FACTURA_COMPRA_MIRROR:#{invoice.id}]%")
                   .order(occurred_at: :desc, created_at: :desc)
  end

  def business_account_movements_scope
    AccountMovement.joins(:account).where(accounts: { business_id: current_business.id })
  end

  def account_movements_scope_for_business(business_id)
    AccountMovement.joins(:account).where(accounts: { business_id: business_id })
  end

  def remove_invoice_related_records!(invoice)
    linked_debts = invoice_pending_debts_scope(invoice).includes(:debt_payments, :mirror_debt).to_a
    if invoice.intercompany? && invoice.source_business_id.present?
      linked_debts += Debt.where(business_id: invoice.source_business_id)
                          .where('description LIKE ?', "%[FACTURA_COMPRA_MIRROR:#{invoice.id}]%")
                          .to_a
    end

    mirror_debts = linked_debts.filter_map(&:mirror_debt)
    linked_debts = (linked_debts + mirror_debts).uniq(&:id)

    linked_debt_ids = linked_debts.map(&:id)

    movements_to_destroy = []
    movements_to_destroy.concat(invoice_payment_movements_scope(invoice).to_a)

    if invoice.intercompany? && invoice.source_business_id.present?
      movements_to_destroy.concat(
        account_movements_scope_for_business(invoice.source_business_id)
          .where('account_movements.description LIKE ?', "%[FACTURA_COMPRA_MIRROR:#{invoice.id}]%")
          .to_a
      )
    end

    linked_debts.group_by(&:business_id).each do |business_id, debts|
      debt_ids_for_business = debts.map(&:id)
      debt_payment_ids_for_business = debts.flat_map { |debt| debt.debt_payments.map(&:id) }
      movement_scope = account_movements_scope_for_business(business_id)

      debt_ids_for_business.each do |debt_id|
        movements_to_destroy.concat(
          movement_scope.where('account_movements.description ILIKE ?', "%[DEBT:#{debt_id}]%").to_a
        )
      end

      debt_payment_ids_for_business.each do |payment_id|
        movements_to_destroy.concat(
          movement_scope.where('account_movements.description ILIKE ?', "%[DP:#{payment_id}]%").to_a
        )
      end
    end

    movements_to_destroy.uniq!(&:id)
    movements_to_destroy.each(&:destroy!)

    if linked_debt_ids.any?
      Debt.where(mirror_debt_id: linked_debt_ids).update_all(
        mirror_debt_id: nil,
        mirror_sync_enabled: false,
        updated_at: Time.current,
      )
      linked_debts.each do |debt|
        debt.update_columns(mirror_debt_id: nil, mirror_sync_enabled: false, updated_at: Time.current)
      end
    end

    linked_debts.each(&:destroy!)
  end

  def invoice_pending_debts_scope(invoice)
    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    escaped_reference = ActiveRecord::Base.sanitize_sql_like(invoice_reference)

    current_business.debts
                    .where(debt_kind: 'payable')
                    .where(
                      'description LIKE :tag OR description LIKE :legacy',
                      tag: "%[FACTURA_COMPRA:#{invoice.id}]%",
                      legacy: "Saldo pendiente factura #{escaped_reference}%"
                    )
  end

  def find_invoice_pending_debt(invoice)
    invoice_pending_debts_scope(invoice).order(created_at: :desc).first
  end

  def sync_intercompany_pending_debts!(invoice, source_business:)
    total_invoice_bs = invoice.total_bs.to_d.round(2)
    total_paid_bs = invoice_payment_movements_scope(invoice).sum(:amount).to_d.round(2)
    pending_amount_bs = (total_invoice_bs - total_paid_bs).round(2)
    pending_amount_bs = 0.to_d if pending_amount_bs <= 0

    rate = invoice.tasa_dolar.to_d
    pending_amount_usd = if pending_amount_bs.positive?
                           rate.positive? ? (pending_amount_bs / rate).round(2) : pending_amount_bs.round(2)
                         else
                           0.to_d
                         end

    payable_debt = find_invoice_pending_debt(invoice)
    receivable_debt = payable_debt&.mirror_debt || find_source_mirror_pending_debt(invoice)

    mark_pending_payment = ActiveModel::Type::Boolean.new.cast(params[:mark_pending_payment])
    due_on = parse_filter_date(params[:pending_due_on].to_s.strip)

    if pending_amount_usd <= 0
      destroy_linked_debt_pair!(payable_debt, receivable_debt)
      return
    end

    should_persist_pending = mark_pending_payment || payable_debt.present? || receivable_debt.present?
    return unless should_persist_pending

    payable_debt ||= build_intercompany_payable_debt!(invoice, source_business: source_business, due_on: due_on)
    receivable_debt ||= build_intercompany_receivable_debt!(invoice, source_business: source_business, due_on: due_on)

    if payable_debt.blank? || receivable_debt.blank?
      @purchase_invoice.errors.add(:base, 'No se pudo crear la deuda espejo interempresa al actualizar la factura.')
      return
    end

    payable_debt.update!(
      amount: pending_amount_usd,
      currency: 'USD',
      due_on: due_on.presence || payable_debt.due_on,
      mirror_sync_enabled: true,
      mirror_debt: receivable_debt,
    )

    receivable_debt.update!(
      amount: pending_amount_usd,
      currency: 'USD',
      due_on: due_on.presence || receivable_debt.due_on,
      mirror_sync_enabled: true,
      mirror_debt: payable_debt,
    )
  end

  def sync_intercompany_payment_movements!(invoice, payments:, source_business:)
    movements_to_remove = invoice_payment_movements_scope(invoice).to_a + source_invoice_payment_movements_scope(invoice).to_a
    movements_to_remove.uniq!(&:id)
    movements_to_remove.each(&:destroy!)

    occurred_at = invoice.fecha_emision.presence || Time.current
    outgoing_description = "Pago factura inter-empresa ##{invoice.id} a #{source_business.name} [FACTURA_COMPRA:#{invoice.id}]"

    Array(payments).each do |entry|
      account = entry[:account]
      amount = entry[:amount].to_d
      next if account.blank? || amount <= 0

      attrs = {
        movement_kind: 'expense',
        amount: amount,
        description: outgoing_description,
        occurred_at: occurred_at,
      }
      attrs[:payment_method] = 'transfer' if account.account_type == 'bank_account'
      account.account_movements.create!(attrs)
    end

    grouped_by_source = Array(payments).group_by { |entry| entry[:source_account]&.id }
    grouped_by_source.each_value do |rows|
      source_account = rows.first[:source_account]
      next if source_account.blank?

      total_amount = rows.sum { |entry| entry[:amount].to_d }.round(2)
      next unless total_amount.positive?

      source_account.account_movements.create!(
        movement_kind: 'income',
        amount: total_amount,
        description: "Cobro factura inter-empresa ##{invoice.id} desde #{current_business.name} [FACTURA_COMPRA_MIRROR:#{invoice.id}]",
        occurred_at: occurred_at,
        payment_method: (source_account.account_type == 'bank_account' ? 'transfer' : nil),
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
  end

  def find_source_mirror_pending_debt(invoice)
    return nil if invoice.source_business_id.blank?

    Debt.where(business_id: invoice.source_business_id, debt_kind: 'receivable')
        .where('description LIKE ?', "%[FACTURA_COMPRA_MIRROR:#{invoice.id}]%")
        .order(created_at: :desc)
        .first
  end

  def build_intercompany_payable_debt!(invoice, source_business:, due_on:)
    client = find_or_create_intercompany_counterparty_client!(
      owner_business: current_business,
      counterparty_business: source_business,
    )

    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    current_business.debts.create!(
      debt_kind: 'payable',
      cliente: client,
      name: source_business.name,
      description: "Saldo pendiente factura inter-empresa #{invoice_reference} [FACTURA_COMPRA:#{invoice.id}] [IC_MIRROR]",
      amount: 0.01.to_d,
      currency: 'USD',
      issued_on: invoice.fecha_emision&.to_date || Date.current,
      due_on: due_on,
      mirror_sync_enabled: true,
    )
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    nil
  end

  def build_intercompany_receivable_debt!(invoice, source_business:, due_on:)
    client = find_or_create_intercompany_counterparty_client!(
      owner_business: source_business,
      counterparty_business: current_business,
    )

    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    source_business.debts.create!(
      debt_kind: 'receivable',
      cliente: client,
      name: current_business.name,
      description: "Cuenta por cobrar factura inter-empresa #{invoice_reference} [FACTURA_COMPRA_MIRROR:#{invoice.id}] [IC_MIRROR]",
      amount: 0.01.to_d,
      currency: 'USD',
      issued_on: invoice.fecha_emision&.to_date || Date.current,
      due_on: due_on,
      mirror_sync_enabled: true,
    )
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    nil
  end

  def destroy_linked_debt_pair!(payable_debt, receivable_debt)
    linked = [payable_debt, receivable_debt].compact.uniq(&:id)
    return if linked.empty?

    linked_ids = linked.map(&:id)
    Debt.where(mirror_debt_id: linked_ids).update_all(
      mirror_debt_id: nil,
      mirror_sync_enabled: false,
      updated_at: Time.current,
    )
    linked.each { |debt| debt.update_columns(mirror_debt_id: nil, mirror_sync_enabled: false, updated_at: Time.current) }
    linked.each(&:destroy!)
  end

  def find_or_create_intercompany_counterparty_client!(owner_business:, counterparty_business:)
    normalized_name = counterparty_business.name.to_s.strip.downcase
    existing = owner_business.clientes.where('LOWER(TRIM(name)) = ?', normalized_name).first
    return existing if existing.present?

    owner_business.clientes.create!(
      name: counterparty_business.name,
      document_type: 'J',
      document_number: normalize_intercompany_rif_document_number(counterparty_business.rif),
    )
  end

  def normalize_intercompany_rif_document_number(raw_rif)
    raw_rif.to_s.upcase.gsub(/[^A-Z0-9]/, '').sub(/\A[JVEG]/, '')
  end

  def aggregate_source_stock_rows_for_invoice_items(items, source_business:)
    aggregated = Hash.new(0.to_d)

    items.each do |item|
      source_product = resolve_intercompany_source_product_for_item(item, source_business: source_business)
      next if source_product.blank?

      source_rows_for_item(item: item, source_product: source_product).each do |row|
        key = [row[:source_product_id], row[:source_variation_id]]
        aggregated[key] += row[:quantity].to_d
      end
    end

    aggregated.map do |(source_product_id, source_variation_id), quantity|
      {
        source_product_id: source_product_id,
        source_variation_id: source_variation_id,
        quantity: quantity,
      }
    end
  end

  def normalize_intercompany_items_for_destination!(invoice, source_business:)
    items = invoice.purchase_invoice_items.reject(&:marked_for_destruction?)
    return if items.empty?

    items.each do |item|
      source_product = resolve_intercompany_source_product_for_item(item, source_business: source_business)
      next if source_product.blank?

      destination_product = destination_product_for_source(source_product: source_product, source_business: source_business)
      next if destination_product.blank?

      item.producto = destination_product
      item.product_name = destination_product.descripcion
      normalize_intercompany_item_variation_breakdown!(
        item: item,
        source_product: source_product,
        destination_product: destination_product,
      )
    end
  end

  def destination_product_for_source(source_product:, source_business:)
    destination_product = current_business.productos.find_by(
      source_business_id: source_business.id,
      source_product_id: source_product.id,
    )
    return destination_product if destination_product.present?

    destination_category = current_business.categorias.find_or_create_by!(
      nombre: source_product.categoria&.nombre.presence || 'General',
    )

    preset = nil
    if source_product.profit_margin_preset.present?
      preset = current_business.profit_margin_presets.find_or_create_by!(
        percentage: source_product.profit_margin_preset.percentage,
      )
    end

    destination_product = current_business.productos.create!(
      descripcion: source_product.descripcion,
      presentation: source_product.presentation,
      cant_presentation: source_product.cant_presentation,
      allow_unpack: source_product.allow_unpack,
      precio_venta_usd: source_product.precio_venta_usd,
      porcentaje_ganancia: source_product.porcentaje_ganancia,
      categoria: destination_category,
      profit_margin_preset: preset,
      exento: source_product.respond_to?(:exento) ? source_product.exento : false,
      source_business_id: source_business.id,
      source_product_id: source_product.id,
    )

    source_product.product_variations.order(:id).find_each do |variation|
      destination_product.product_variations.create!(
        description: variation.description,
        safety_stock: variation.safety_stock,
      )
    end

    if source_product.foto.attached? && !destination_product.foto.attached?
      destination_product.foto.attach(source_product.foto.blob)
    end

    destination_product
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    nil
  end

  def normalize_intercompany_item_variation_breakdown!(item:, source_product:, destination_product:)
    source_variations = source_product.product_variations.order(:id).to_a
    destination_by_desc = destination_product.product_variations.order(:id).index_by do |variation|
      variation.description.to_s.strip.downcase
    end

    rows = item.variation_breakdown.is_a?(Array) ? item.variation_breakdown : []
    normalized_rows = rows.filter_map do |raw_row|
      next unless raw_row.is_a?(Hash)

      quantity = (raw_row['quantity'] || raw_row[:quantity]).to_d
      next unless quantity.positive?

      source_variation = resolve_source_variation_for_item_row(
        source_product: source_product,
        source_variations: source_variations,
        destination_product: destination_product,
        row: raw_row,
      )
      next if source_variation.blank?

      destination_variation = destination_by_desc[source_variation.description.to_s.strip.downcase]
      if destination_variation.blank?
        destination_variation = destination_product.product_variations.create!(
          description: source_variation.description,
          safety_stock: source_variation.safety_stock,
        )
        destination_by_desc[source_variation.description.to_s.strip.downcase] = destination_variation
      end

      {
        'variation_id' => destination_variation.id,
        'description' => destination_variation.description,
        'quantity' => quantity.to_f,
      }
    end

    if normalized_rows.empty? && source_variations.one?
      source_variation = source_variations.first
      destination_variation = destination_by_desc[source_variation.description.to_s.strip.downcase]
      if destination_variation.present? && item.cantidad.to_d.positive?
        normalized_rows = [{
          'variation_id' => destination_variation.id,
          'description' => destination_variation.description,
          'quantity' => item.cantidad.to_d.to_f,
        }]
      end
    end

    item.variation_breakdown = normalized_rows
  end

  def resolve_intercompany_source_product_for_item(item, source_business:)
    destination_product = item.producto

    if destination_product.present?
      return destination_product if destination_product.business_id == source_business.id

      mapped_source_id = destination_product.source_product_id.to_i
      if destination_product.source_business_id == source_business.id && mapped_source_id.positive?
        mapped = source_business.productos.find_by(id: mapped_source_id)
        return mapped if mapped.present?
      end
    end

    lookup_name = destination_product&.descripcion.to_s.presence || item.product_name.to_s
    normalized_name = lookup_name.to_s.strip.downcase
    if normalized_name.blank?
      @purchase_invoice.errors.add(:base, 'No se pudo resolver el producto origen para sincronizar stock interempresa.')
      return nil
    end

    product = source_business.productos.find_by('LOWER(TRIM(productos.descripcion)) = ?', normalized_name)
    return product if product.present?

    @purchase_invoice.errors.add(:base,
                                 "No se encontró en negocio origen el producto '#{lookup_name}' para sincronizar stock interempresa.")
    nil
  end

  def source_rows_for_item(item:, source_product:)
    destination_product = item.producto
    source_variations = source_product.product_variations.order(:id).to_a
    raw_rows = item.variation_breakdown.is_a?(Array) ? item.variation_breakdown : []

    rows = raw_rows.filter_map do |raw_row|
      next unless raw_row.is_a?(Hash)

      quantity = (raw_row['quantity'] || raw_row[:quantity]).to_d
      next unless quantity.positive?

      source_variation = resolve_source_variation_for_item_row(
        source_product: source_product,
        source_variations: source_variations,
        destination_product: destination_product,
        row: raw_row,
      )
      next if source_variation.blank?

      {
        source_product_id: source_product.id,
        source_variation_id: source_variation.id,
        quantity: quantity,
      }
    end

    if rows.empty? && source_variations.one?
      quantity = item.cantidad.to_d
      if quantity.positive?
        rows = [{
          source_product_id: source_product.id,
          source_variation_id: source_variations.first.id,
          quantity: quantity,
        }]
      end
    end

    rows
  end

  def resolve_source_variation_for_item_row(source_product:, source_variations:, destination_product:, row:)
    variation_id_raw = row['variation_id'] || row[:variation_id]
    if variation_id_raw.present?
      variation_id = variation_id_raw.to_i
      variation = source_variations.find { |entry| entry.id == variation_id }
      return variation if variation.present?

      destination_variation = destination_product&.product_variations&.find_by(id: variation_id)
      if destination_variation.present?
        mapped = source_variations.find do |entry|
          entry.description.to_s.strip.casecmp(destination_variation.description.to_s.strip).zero?
        end
        return mapped if mapped.present?
      end
    end

    description = (row['description'] || row[:description]).to_s.strip
    if description.present?
      variation = source_variations.find do |entry|
        entry.description.to_s.strip.casecmp(description).zero?
      end
      return variation if variation.present?
    end

    return source_variations.first if source_variations.one?

    @purchase_invoice.errors.add(:base,
                                 "No se pudo resolver variación origen para producto '#{source_product.descripcion}'.")
    nil
  end

  def consume_source_stock_rows!(rows:)
    rows.each do |row|
      consume_source_variation_units!(
        source_product_id: row[:source_product_id],
        source_variation_id: row[:source_variation_id],
        quantity: row[:quantity],
      )
      break if @purchase_invoice.errors.any?
    end
  end

  def restore_source_stock_rows!(rows:)
    rows.each do |row|
      restore_source_variation_units!(
        source_product_id: row[:source_product_id],
        source_variation_id: row[:source_variation_id],
        quantity: row[:quantity],
      )
      break if @purchase_invoice.errors.any?
    end
  end

  def consume_source_variation_units!(source_product_id:, source_variation_id:, quantity:)
    remaining = quantity.to_d
    return unless remaining.positive?

    rows_scope = source_variation_stock_rows_scope(
      source_product_id: source_product_id,
      source_variation_id: source_variation_id,
    )

    available = rows_scope.sum(:quantity_remaining).to_d
    if available < remaining
      @purchase_invoice.errors.add(
        :base,
        "Stock insuficiente en origen para sincronizar edición interempresa. Disponible: #{available.to_f.round(4)}; requerido: #{remaining.to_f.round(4)}."
      )
      return
    end

    rows_scope.each do |variation_row|
      break if remaining <= 0

      variation_row.lock!
      lot = variation_row.stock_lot
      available_in_row = variation_row.quantity_remaining.to_d
      next unless available_in_row.positive?

      consumed = [available_in_row, remaining].min
      variation_row.update!(quantity_remaining: available_in_row - consumed)
      lot.sync_quantity_remaining_from_variations!
      remaining -= consumed
    end
  end

  def restore_source_variation_units!(source_product_id:, source_variation_id:, quantity:)
    remaining = quantity.to_d
    return unless remaining.positive?

    rows_scope = source_variation_stock_rows_scope(
      source_product_id: source_product_id,
      source_variation_id: source_variation_id,
    )

    recoverable = rows_scope.sum(Arel.sql('GREATEST(stock_lot_variations.quantity_in - stock_lot_variations.quantity_remaining, 0)')).to_d
    if recoverable < remaining
      @purchase_invoice.errors.add(
        :base,
        "No se pudo restablecer todo el stock en origen para la edición interempresa. Recuperable: #{recoverable.to_f.round(4)}; a restaurar: #{remaining.to_f.round(4)}."
      )
      return
    end

    rows_scope.each do |variation_row|
      break if remaining <= 0

      variation_row.lock!
      lot = variation_row.stock_lot
      quantity_in = variation_row.quantity_in.to_d
      quantity_remaining = variation_row.quantity_remaining.to_d
      consumed_in_row = [quantity_in - quantity_remaining, 0.to_d].max
      next unless consumed_in_row.positive?

      restored = [consumed_in_row, remaining].min
      variation_row.update!(quantity_remaining: quantity_remaining + restored)
      lot.sync_quantity_remaining_from_variations!
      remaining -= restored
    end
  end

  def source_variation_stock_rows_scope(source_product_id:, source_variation_id:)
    StockLotVariation
      .joins(:stock_lot)
      .where(stock_lot_variations: { product_variation_id: source_variation_id })
      .where(stock_lots: { producto_id: source_product_id })
      .order(Arel.sql('stock_lots.unit_cost_usd DESC, stock_lots.purchased_at ASC, stock_lots.created_at ASC'))
  end
end
