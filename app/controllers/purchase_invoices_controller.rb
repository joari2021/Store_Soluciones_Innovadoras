class PurchaseInvoicesController < ApplicationController
  PER_PAGE = 15
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

    if @purchase_invoice.initial_inventory?
      if @purchase_invoice.save
        redirect_to purchase_invoices_path, notice: 'Inventario inicial registrado correctamente'
      else
        render :new, status: :unprocessable_entity
      end
      return
    end

    @purchase_invoice.valid?
    payment_context = build_invoice_payment_context(@purchase_invoice)

    if @purchase_invoice.errors.any?
      apply_invoice_payment_form_state(payment_context)
      render :new, status: :unprocessable_entity
      return
    end

    PurchaseInvoice.transaction do
      @purchase_invoice.save!
      create_invoice_payment_movements!(@purchase_invoice, payment_context[:payments])
      create_pending_supplier_debt!(@purchase_invoice, payment_context)
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
    if @purchase_invoice.update(purchase_invoice_params)
      success_message = if @purchase_invoice.initial_inventory?
                          'Inventario inicial actualizado'
                        else
                          'Factura actualizada'
                        end

      redirect_to purchase_invoices_path, notice: success_message
    else
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit
    end
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

  def load_bs_accounts
    @bs_accounts = current_business.accounts.where(active: true, currency: 'VES').order(:name)
  end

  def purchase_invoice_params
    params.require(:purchase_invoice).permit(
      :supplier_id,
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
    { account_id: '', amount: '' }
  end

  def apply_invoice_payment_form_state(context)
    @invoice_payment_rows = context[:rows].presence || [default_invoice_payment_row]
    @pending_payment_checked = context[:mark_pending_payment] == true
    @pending_due_on_value = context[:pending_due_on_value].to_s
  end

  def build_invoice_payment_context(invoice)
    rows_for_form = invoice_payment_rows_for_form
    normalized_rows = normalize_invoice_payment_rows(rows_for_form)
    mark_pending_payment = ActiveModel::Type::Boolean.new.cast(params[:mark_pending_payment])
    pending_due_on_raw = params[:pending_due_on].to_s.strip
    pending_due_on = parse_filter_date(pending_due_on_raw)

    payments = build_invoice_payment_records(invoice, normalized_rows)

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

  def build_invoice_payment_records(invoice, normalized_rows)
    account_ids = normalized_rows.map { |row| row[:account_id].to_i }.select(&:positive?).uniq
    accounts_by_id = current_business.accounts.where(id: account_ids).index_by(&:id)

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

      { account: account, amount: amount }
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

  def business_account_movements_scope
    AccountMovement.joins(:account).where(accounts: { business_id: current_business.id })
  end

  def remove_invoice_related_records!(invoice)
    linked_debts = invoice_pending_debts_scope(invoice).includes(:debt_payments).to_a
    linked_debt_ids = linked_debts.map(&:id)
    linked_debt_payment_ids = linked_debts.flat_map { |debt| debt.debt_payments.map(&:id) }

    movements_to_destroy = []
    movements_to_destroy.concat(invoice_payment_movements_scope(invoice).to_a)

    linked_debt_ids.each do |debt_id|
      movements_to_destroy.concat(
        business_account_movements_scope.where('account_movements.description ILIKE ?', "%[DEBT:#{debt_id}]%").to_a
      )
    end

    linked_debt_payment_ids.each do |payment_id|
      movements_to_destroy.concat(
        business_account_movements_scope.where('account_movements.description ILIKE ?', "%[DP:#{payment_id}]%").to_a
      )
    end

    movements_to_destroy.uniq!(&:id)
    movements_to_destroy.each(&:destroy!)

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
end
