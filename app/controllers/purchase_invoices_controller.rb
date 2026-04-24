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
  INVOICE_DELIVERY_STATUS_LABELS = {
    true => 'Entregada',
    false => 'No entregada'
  }.freeze
  INVOICE_DELIVERY_STATUS_BADGE_CLASSES = {
    true => 'border-emerald-200 bg-emerald-50 text-emerald-700',
    false => 'border-slate-300 bg-slate-100 text-slate-700'
  }.freeze

  helper_method :invoice_payment_status_filter_options,
                :invoice_payment_status_for,
                :invoice_payment_status_label,
                :invoice_payment_status_badge_class,
                :invoice_delivery_status_filter_options,
                :invoice_delivery_status_label,
                :invoice_delivery_status_badge_class

  before_action :require_business
  before_action :require_admin
  before_action :ensure_purchase_invoice_columns_loaded
  before_action :set_purchase_invoice, only: %i[show edit update destroy]
  before_action :load_global_suppliers, only: %i[index new edit create update]
  before_action :load_bs_accounts, only: %i[new create]
  before_action :load_intercompany_options, only: %i[new create edit update]
  before_action :load_invoice_payment_summary, only: %i[show edit]

  def index
    base_scope = current_business.purchase_invoices.includes(supplier: :global_supplier)

    @has_purchase_invoices = base_scope.exists?
    @selected_global_supplier_id = params[:global_supplier_id].to_s.strip.presence
    @selected_payment_status = normalize_invoice_payment_status(params[:payment_status])
    @selected_delivery_status = normalize_invoice_delivery_status(params[:delivery_status])
    @fecha_desde = parse_filter_date(params[:fecha_desde])
    @fecha_hasta = parse_filter_date(params[:fecha_hasta])

    if @fecha_desde.present? && @fecha_hasta.present? && @fecha_desde > @fecha_hasta
      @fecha_desde, @fecha_hasta = @fecha_hasta, @fecha_desde
    end

    @fecha_desde_value = normalized_filter_date_value(params[:fecha_desde], @fecha_desde)
    @fecha_hasta_value = normalized_filter_date_value(params[:fecha_hasta], @fecha_hasta)
    @filters_applied = [
      @selected_global_supplier_id,
      @selected_payment_status,
      @selected_delivery_status,
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip
    ].any?(&:present?)

    if @selected_global_supplier_id.present?
      base_scope = base_scope.joins(:supplier).where(suppliers: { global_supplier_id: @selected_global_supplier_id })
    end
    if @selected_delivery_status.present?
      base_scope = base_scope.where(delivered: @selected_delivery_status == 'delivered')
    end

    base_scope = base_scope.where('facturas.fecha_emision >= ?', @fecha_desde.beginning_of_day) if @fecha_desde.present?
    base_scope = base_scope.where('facturas.fecha_emision <= ?', @fecha_hasta.end_of_day) if @fecha_hasta.present?

    ordered_invoices = base_scope.order(fecha_emision: :desc, created_at: :desc).to_a
    initial_inventory_invoices, regular_invoices = ordered_invoices.partition(&:initial_inventory?)
    ordered_invoices = regular_invoices + initial_inventory_invoices
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
    @purchase_invoice = current_business.purchase_invoices.new
    purchase_attrs = purchase_invoice_params.to_h
    resolved_supplier_id = resolve_local_supplier_id_from_global(
      global_supplier_id: purchase_attrs['global_supplier_id'],
      enforce_presence: !intercompany_mode_requested? && requested_invoice_kind != PurchaseInvoice::INVOICE_KIND_INITIAL_INVENTORY,
    )
    purchase_attrs['supplier_id'] = resolved_supplier_id
    purchase_attrs.delete('global_supplier_id')
    @purchase_invoice.assign_attributes(purchase_attrs)
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
        apply_source_stock_movements: @purchase_invoice.stock_delivered?,
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

    update_attrs = purchase_invoice_params.to_h
    resolved_supplier_id = resolve_local_supplier_id_from_global(
      global_supplier_id: update_attrs['global_supplier_id'],
      enforce_presence: !@purchase_invoice.initial_inventory?,
    )
    update_attrs['supplier_id'] = resolved_supplier_id
    update_attrs.delete('global_supplier_id')

    if @purchase_invoice.update(update_attrs)
      unless @purchase_invoice.initial_inventory?
        payment_context = build_invoice_payment_context(@purchase_invoice)
        sync_pending_supplier_debt!(@purchase_invoice, payment_context)
      end

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
      log_intercompany_update_failure!(stage: 'missing_source_business')
      apply_invoice_payment_form_state(default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    requested_source_id = params.dig(:purchase_invoice, :source_business_id).to_s.strip
    if requested_source_id.present? && requested_source_id.to_i != source_business.id
      @purchase_invoice.errors.add(:base, 'No se puede cambiar el negocio origen en una factura interempresa ya creada.')
      log_intercompany_update_failure!(stage: 'source_business_changed')
      apply_invoice_payment_form_state(default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    prior_rows = aggregate_source_stock_rows_for_invoice_items(
      @purchase_invoice.purchase_invoice_items.includes(producto: :product_variations),
      source_business: source_business,
    )
    prior_delivered = @purchase_invoice.stock_delivered?

    if @purchase_invoice.errors.any?
      log_intercompany_update_failure!(stage: 'pre_transaction_validation')
      apply_invoice_payment_form_state(default_invoice_payment_context)
      load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
      render :edit, status: :unprocessable_entity
      return
    end

    PurchaseInvoice.transaction do
      if prior_delivered
        restore_source_stock_rows!(rows: prior_rows)
        if @purchase_invoice.errors.any?
          log_intercompany_update_failure!(stage: 'restore_source_stock_rows')
          raise ActiveRecord::Rollback
        end
      end

      intercompany_update_attrs = purchase_invoice_params.to_h.except('source_business_id', 'intercompany', 'global_supplier_id')
      @purchase_invoice.assign_attributes(intercompany_update_attrs)
      current_delivered = @purchase_invoice.stock_delivered?
      normalize_intercompany_items_for_destination!(@purchase_invoice, source_business: source_business)
      if @purchase_invoice.errors.any?
        log_intercompany_update_failure!(stage: 'normalize_items_for_destination')
        raise ActiveRecord::Rollback
      end

      payment_context = build_invoice_payment_context(@purchase_invoice, source_business: source_business)
      if @purchase_invoice.errors.any?
        log_intercompany_update_failure!(stage: 'build_payment_context')
        raise ActiveRecord::Rollback
      end

      @purchase_invoice.save!

      current_rows = aggregate_source_stock_rows_for_invoice_items(
        @purchase_invoice.purchase_invoice_items.includes(producto: :product_variations),
        source_business: source_business,
      )
      if @purchase_invoice.errors.any?
        log_intercompany_update_failure!(stage: 'aggregate_current_source_rows')
        raise ActiveRecord::Rollback
      end

      if current_delivered
        consume_source_stock_rows!(rows: current_rows)
        if @purchase_invoice.errors.any?
          log_intercompany_update_failure!(stage: 'consume_source_stock_rows')
          raise ActiveRecord::Rollback
        end
      end

      if invoice_payment_rows_input_submitted?
        sync_intercompany_payment_movements!(
          @purchase_invoice,
          payments: payment_context[:payments],
          source_business: source_business,
        )
        if @purchase_invoice.errors.any?
          log_intercompany_update_failure!(stage: 'sync_payment_movements')
          raise ActiveRecord::Rollback
        end
      end

      sync_intercompany_pending_debts!(
        @purchase_invoice,
        source_business: source_business,
        payment_context: payment_context,
      )
      if @purchase_invoice.errors.any?
        log_intercompany_update_failure!(stage: 'sync_pending_debts')
        raise ActiveRecord::Rollback
      end
    end

    if @purchase_invoice.errors.any?
      log_intercompany_update_failure!(stage: 'post_transaction')
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

    log_intercompany_update_exception!(e)

    apply_invoice_payment_form_state(payment_context || default_invoice_payment_context)
    load_invoice_payment_summary unless @purchase_invoice.initial_inventory?
    render :edit, status: :unprocessable_entity
  rescue StandardError => e
    @purchase_invoice.errors.add(:base, 'Ocurrió un error inesperado al actualizar la factura interempresa.')
    log_intercompany_update_exception!(e)

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

  def ensure_purchase_invoice_columns_loaded
    return if PurchaseInvoice.attribute_names.include?('invoice_kind')

    PurchaseInvoice.reset_column_information
  end

  def set_purchase_invoice
    @purchase_invoice = current_business.purchase_invoices.find(params[:id])
  end

  def load_global_suppliers
    @available_global_suppliers = GlobalSupplier.where(active: true)
                                 .order(Arel.sql('LOWER(global_suppliers.name) ASC'))
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
      :global_supplier_id,
      :intercompany,
      :source_business_id,
      :fecha_emision,
      :tasa_dolar,
      :descuento_usd,
      :descuento_bs,
      :delivered,
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

  def resolve_local_supplier_id_from_global(global_supplier_id:, enforce_presence:)
    normalized_global_id = global_supplier_id.to_s.strip
    if normalized_global_id.blank?
      @purchase_invoice&.errors&.add(:base, 'debe seleccionar un proveedor global.') if enforce_presence
      return nil
    end

    global_supplier = GlobalSupplier.find_by(id: normalized_global_id)
    unless global_supplier
      @purchase_invoice&.errors&.add(:base, 'el proveedor global seleccionado no es válido.')
      return nil
    end

    local_supplier = current_business.suppliers.find_or_initialize_by(global_supplier_id: global_supplier.id)
    if local_supplier.new_record?
      local_supplier.assign_attributes(
        nombre: global_supplier.name,
        rif: global_supplier.rif,
        telefono: global_supplier.phone,
        telefono_pago_movil: global_supplier.mobile_payment_phone,
        email: global_supplier.email,
        direccion: global_supplier.address,
        nro_cuenta: global_supplier.bank_account_number,
        pricing_currency_priority: global_supplier.pricing_currency_priority,
        default_exento: global_supplier.default_exento,
      )
      local_supplier.save!
    end

    local_supplier.id
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice&.errors&.add(:base, e.record.errors.full_messages.to_sentence.presence || 'no se pudo preparar el proveedor local de compatibilidad.')
    nil
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
            elsif Current.user.present?
              assignment_ids = Current.user.business_user_assignments.active.select(:business_id)
              Business.where(id: assignment_ids)
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
    payment_input_submitted = invoice_payment_rows_input_submitted?
    mark_pending_payment = ActiveModel::Type::Boolean.new.cast(params[:mark_pending_payment])
    pending_due_on_raw = params[:pending_due_on].to_s.strip
    pending_due_on = parse_filter_date(pending_due_on_raw)

    if invoice.persisted? && !payment_input_submitted
      existing_pending_debt = find_invoice_pending_debt(invoice)
      total_invoice_bs = invoice.total_bs.to_d.round(2)
      total_paid_bs = invoice_payment_movements_scope(invoice).sum(:amount).to_d.round(2)
      debt_paid_bs = if existing_pending_debt.present?
                       amount_in_bs_for_invoice(
                         invoice: invoice,
                         amount: existing_pending_debt.paid_amount.to_d.round(2),
                         currency: existing_pending_debt.currency
                       )
                     else
                       0.to_d
                     end
      total_paid_bs = (total_paid_bs + debt_paid_bs).round(2)
      pending_amount_bs = (total_invoice_bs - total_paid_bs).round(2)

      pending_amount_bs = 0.to_d if pending_amount_bs.abs < 0.01.to_d
      effective_rate = invoice_effective_usd_rate(invoice)
      total_invoice_usd = effective_rate.positive? ? (total_invoice_bs / effective_rate).round(2) : invoice.monto_total.to_d.round(2)
      total_paid_usd = effective_rate.positive? ? (total_paid_bs / effective_rate).round(2) : 0.to_d
      pending_amount_usd = effective_rate.positive? ? (pending_amount_bs / effective_rate).round(2) : [total_invoice_usd - total_paid_usd, 0.to_d].max

      effective_mark_pending = existing_pending_debt.present? || pending_amount_bs.positive?
      effective_pending_due_on = existing_pending_debt&.due_on

      return {
        rows: rows_for_form,
        mark_pending_payment: effective_mark_pending,
        pending_due_on: effective_pending_due_on,
        pending_due_on_value: normalized_filter_date_value('', effective_pending_due_on),
        payments: [],
        total_invoice_bs: total_invoice_bs,
        total_paid_bs: total_paid_bs,
        pending_amount_bs: [pending_amount_bs, 0.to_d].max,
        total_invoice_usd: [total_invoice_usd, 0.to_d].max,
        total_paid_usd: [total_paid_usd, 0.to_d].max,
        pending_amount_usd: [pending_amount_usd, 0.to_d].max
      }
    end

    payments = build_invoice_payment_records(invoice, normalized_rows, source_business: source_business)

    total_invoice_bs = invoice.total_bs.to_d.round(2)
    total_paid_bs = payments.sum { |entry| entry[:amount].to_d }.round(2)
    pending_amount_bs = (total_invoice_bs - total_paid_bs).round(2)
    pending_amount_bs = 0.to_d if pending_amount_bs.abs < 0.01.to_d
    effective_rate = invoice_effective_usd_rate(invoice)
    total_invoice_usd = effective_rate.positive? ? (total_invoice_bs / effective_rate).round(2) : invoice.monto_total.to_d.round(2)
    total_paid_usd = effective_rate.positive? ? (total_paid_bs / effective_rate).round(2) : 0.to_d
    pending_amount_usd = effective_rate.positive? ? (pending_amount_bs / effective_rate).round(2) : [total_invoice_usd - total_paid_usd, 0.to_d].max

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
      pending_amount_bs: [pending_amount_bs, 0.to_d].max,
      total_invoice_usd: [total_invoice_usd, 0.to_d].max,
      total_paid_usd: [total_paid_usd, 0.to_d].max,
      pending_amount_usd: [pending_amount_usd, 0.to_d].max
    }
  end

  def invoice_payment_input_submitted?
    params.key?(:invoice_payments) || params.key?(:mark_pending_payment) || params.key?(:pending_due_on)
  end

  def invoice_payment_rows_input_submitted?
    params.key?(:invoice_payments)
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
    occurred_at = movement_occurred_at_for_invoice(invoice)
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
    pending_amount_usd = payment_context[:pending_amount_usd].to_d.round(2)
    return unless pending_amount_usd.positive?

    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    supplier_name = invoice.supplier_display_name

    current_business.debts.create!(
      debt_kind: 'payable',
      name: supplier_name,
      acreedor: supplier_name,
      description: "Saldo pendiente factura #{invoice_reference} [FACTURA_COMPRA:#{invoice.id}]",
      amount: pending_amount_usd,
      currency: 'USD',
      issued_on: invoice.fecha_emision&.to_date || Date.current,
      due_on: payment_context[:pending_due_on]
    )
  end

  def sync_pending_supplier_debt!(invoice, payment_context)
    pending_amount_usd = payment_context[:pending_amount_usd].to_d.round(2)
    existing_pending_debt = find_invoice_pending_debt(invoice)
    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    supplier_name = invoice.supplier_display_name
    due_on = payment_context[:pending_due_on].presence || existing_pending_debt&.due_on

    if pending_amount_usd <= 0
      return if existing_pending_debt.blank?

      if existing_pending_debt.debt_payments.exists?
        existing_pending_debt.update!(
          name: supplier_name,
          acreedor: supplier_name,
          amount: existing_pending_debt.paid_amount.to_d.round(2),
          currency: 'USD',
          due_on: due_on
        )
      else
        existing_pending_debt.destroy!
      end
      return
    end

    if existing_pending_debt.present?
      debt_paid_usd = existing_pending_debt.paid_amount.to_d.round(2)
      existing_pending_debt.update!(
        name: supplier_name,
        acreedor: supplier_name,
        description: "Saldo pendiente factura #{invoice_reference} [FACTURA_COMPRA:#{invoice.id}]",
        amount: (pending_amount_usd + debt_paid_usd).round(2),
        currency: 'USD',
        issued_on: invoice.fecha_emision&.to_date || Date.current,
        due_on: due_on
      )
      return
    end

    create_pending_supplier_debt!(invoice, payment_context)
  end

  def build_invoice_payment_movement_description(invoice)
    invoice_reference = invoice.numero.to_s.strip.presence || "##{invoice.id}"
    "Pago factura compra #{invoice_reference} - #{invoice.supplier_display_name} [FACTURA_COMPRA:#{invoice.id}]"
  end

  def movement_occurred_at_for_invoice(invoice)
    caracas_now = Time.current.in_time_zone('America/Caracas')
    payment_date = invoice.fecha_emision&.to_date
    return caracas_now if payment_date.blank?

    caracas_now.change(year: payment_date.year, month: payment_date.month, day: payment_date.day)
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

  def normalize_invoice_delivery_status(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    %w[delivered not_delivered].include?(value) ? value : nil
  end

  def invoice_delivery_status_filter_options
    [
      ['Todos los estados de entrega', ''],
      ['Entregada', 'delivered'],
      ['No entregada', 'not_delivered']
    ]
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

  def invoice_delivery_status_label(invoice)
    key = invoice.stock_delivered? ? true : false
    INVOICE_DELIVERY_STATUS_LABELS[key]
  end

  def invoice_delivery_status_badge_class(invoice)
    key = invoice.stock_delivered? ? true : false
    INVOICE_DELIVERY_STATUS_BADGE_CLASSES[key]
  end

  def build_invoice_payment_status_map(invoices)
    invoices.each_with_object({}) do |invoice, map|
      if invoice.initial_inventory?
        map[invoice.id] = 'paid'
        next
      end

      total_paid_bs = invoice_payment_movements_scope(invoice).sum(:amount).to_d.round(2)
      pending_debt = find_invoice_pending_debt(invoice)
      pending_balance_bs = pending_debt_balance_in_bs(invoice: invoice, debt: pending_debt)

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

    @invoice_payment_movements_usd_map = @invoice_payment_movements.each_with_object({}) do |movement, hash|
      hash[movement.id] = amount_in_usd_for_date(
        amount: movement.amount.to_d,
        currency: movement.account&.currency,
        on_date: movement.occurred_at
      )
    end

    @invoice_total_usd_summary = @purchase_invoice.monto_total.to_d.round(2)
    direct_paid_usd = @invoice_payment_movements_usd_map.values.sum(&:to_d).round(2)

    pending_balance = pending_debt_balance_in_bs(invoice: @purchase_invoice, debt: @invoice_pending_debt)
    @invoice_pending_balance_bs = [pending_balance, 0.to_d].max
    @invoice_debt_assigned_bs = pending_debt_amount_in_bs(invoice: @purchase_invoice, debt: @invoice_pending_debt)
    @invoice_total_paid_bs = [@purchase_invoice.total_bs.to_d - @invoice_pending_balance_bs, 0.to_d].max.round(2)

    if @invoice_pending_debt.present?
      debt_amount_usd = debt_amount_usd_for_summary(@invoice_pending_debt)
      debt_paid_usd = debt_paid_usd_for_summary(@invoice_pending_debt)
      debt_pending_usd = [debt_amount_usd - debt_paid_usd, 0.to_d].max.round(2)

      @invoice_debt_assigned_usd = debt_amount_usd
      @invoice_pending_balance_usd = debt_pending_usd
      @invoice_total_paid_usd = [@invoice_total_usd_summary - debt_pending_usd, 0.to_d].max.round(2)
      @invoice_direct_paid_usd = [@invoice_total_paid_usd - debt_paid_usd, 0.to_d].max.round(2)
    else
      @invoice_debt_assigned_usd = 0.to_d
      @invoice_pending_balance_usd = [@invoice_total_usd_summary - direct_paid_usd, 0.to_d].max.round(2)
      @invoice_total_paid_usd = direct_paid_usd
      @invoice_direct_paid_usd = direct_paid_usd
    end
  end

  def debt_amount_usd_for_summary(debt)
    amount_in_usd_for_date(
      amount: debt.amount.to_d,
      currency: debt.currency,
      on_date: debt.issued_on
    )
  end

  def debt_paid_usd_for_summary(debt)
    debt.debt_payments.to_a.sum do |payment|
      amount_in_usd_for_date(
        amount: payment.amount.to_d,
        currency: payment.currency,
        on_date: payment.occurred_at
      )
    end.round(2)
  end

  def amount_in_usd_for_date(amount:, currency:, on_date:)
    source_currency = currency.to_s.upcase
    source_amount = amount.to_d
    return source_amount.round(2) if source_currency.blank? || source_currency == 'USD'

    converted = CurrencyConverter.convert(
      amount: source_amount,
      from_currency: source_currency,
      to_currency: 'USD',
      on_date: on_date,
    )

    converted&.dig(:amount).to_d.round(2)
  end

  def pending_debt_balance_in_bs(invoice:, debt:)
    return 0.to_d if debt.blank?

    amount_in_bs_for_invoice(
      invoice: invoice,
      amount: debt.balance.to_d.round(2),
      currency: debt.currency
    )
  end

  def pending_debt_amount_in_bs(invoice:, debt:)
    return 0.to_d if debt.blank?

    amount_in_bs_for_invoice(
      invoice: invoice,
      amount: debt.amount.to_d.round(2),
      currency: debt.currency
    )
  end

  def amount_in_bs_for_invoice(invoice:, amount:, currency:)
    source_currency = currency.to_s.upcase
    source_amount = amount.to_d.round(2)
    return source_amount if source_currency == 'VES' || source_currency.blank?

    if source_currency == 'USD'
      rate = invoice_effective_usd_rate(invoice)
      return (source_amount * rate).round(2) if rate.positive?
    end

    converted = CurrencyConverter.convert(
      amount: source_amount,
      from_currency: source_currency,
      to_currency: 'VES',
      on_date: invoice&.fecha_emision&.to_date || Date.current
    )
    converted&.dig(:amount).to_d.round(2)
  end

  def invoice_effective_usd_rate(invoice)
    explicit_rate = invoice&.tasa_dolar.to_d
    return explicit_rate.round(8) if explicit_rate.positive?

    total_bs = invoice&.total_bs.to_d
    total_usd = invoice&.monto_total.to_d
    if total_bs.positive? && total_usd.positive?
      return (total_bs / total_usd).round(8)
    end

    CurrencyConverter.rate_to_ves('USD', on_date: invoice&.fecha_emision&.to_date || Date.current).to_d.round(8)
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
    if invoice.intercompany? && invoice.source_business_id.present? && invoice.stock_delivered?
      source_business = invoice.source_business
      if source_business.present?
        source_rows = aggregate_source_stock_rows_for_invoice_items(
          invoice.purchase_invoice_items.includes(producto: :product_variations),
          source_business: source_business,
        )
        restore_source_stock_rows!(rows: source_rows)
        raise ActiveRecord::RecordInvalid, @purchase_invoice if @purchase_invoice.errors.any?
      end
    end

    linked_debts = invoice_pending_debts_scope(invoice).includes(:debt_payments, :mirror_debt).to_a
    if invoice.intercompany? && invoice.source_business_id.present?
      linked_debts += Debt.where(business_id: invoice.source_business_id)
                          .where('description LIKE ?', "%[FACTURA_COMPRA_MIRROR:#{invoice.id}]%")
                          .to_a
    end

    mirror_debts = linked_debts.filter_map(&:mirror_debt)
    linked_debts = (linked_debts + mirror_debts).uniq(&:id)
    linked_debt_payments = linked_debts.flat_map { |debt| debt.debt_payments.to_a }.uniq(&:id)
    linked_payment_ids = linked_debt_payments.map(&:id)

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

    if linked_payment_ids.any?
      movements_to_destroy.concat(
        AccountMovement
          .where('account_movements.description ILIKE ANY ( ARRAY[?] )', linked_payment_ids.map { |payment_id| "%[MIRROR_FROM_DP:#{payment_id}]%" })
          .to_a
      )
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

    linked_debt_payments.each(&:destroy!)
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

  def sync_intercompany_pending_debts!(invoice, source_business:, payment_context: nil)
    pending_amount_usd = if payment_context.present?
                           payment_context[:pending_amount_usd].to_d.round(2)
                         else
                           total_invoice_bs = invoice.total_bs.to_d.round(2)
                           rate = invoice.tasa_dolar.to_d
                           if rate.positive?
                             (total_invoice_bs / rate).round(2)
                           else
                             invoice.monto_total.to_d.round(2)
                           end
                         end

    payable_debt = find_invoice_pending_debt(invoice)
    receivable_debt = payable_debt&.mirror_debt || find_source_mirror_pending_debt(invoice)

    due_on = payment_context&.dig(:pending_due_on).presence || parse_filter_date(params[:pending_due_on].to_s.strip)

    if pending_amount_usd <= 0
      preserve_payable = payable_debt.present? && payable_debt.debt_payments.exists?
      preserve_receivable = receivable_debt.present? && receivable_debt.debt_payments.exists?

      if !preserve_payable && !preserve_receivable
        destroy_linked_debt_pair!(payable_debt, receivable_debt)
        return
      end

      if payable_debt.present?
        payable_paid = payable_debt.paid_amount.to_d.round(2)
        payable_debt.update!(
          amount: payable_paid.positive? ? payable_paid : 0.01.to_d,
          currency: 'USD',
          acreedor: source_business.name,
          due_on: due_on.presence || payable_debt.due_on,
          mirror_sync_enabled: true,
          mirror_debt: receivable_debt,
        )
      end

      if receivable_debt.present?
        receivable_paid = receivable_debt.paid_amount.to_d.round(2)
        receivable_debt.update!(
          amount: receivable_paid.positive? ? receivable_paid : 0.01.to_d,
          currency: 'USD',
          due_on: due_on.presence || receivable_debt.due_on,
          mirror_sync_enabled: true,
          mirror_debt: payable_debt,
        )
      end

      return
    end

    payable_debt ||= build_intercompany_payable_debt!(invoice, source_business: source_business, due_on: due_on)
    receivable_debt ||= build_intercompany_receivable_debt!(invoice, source_business: source_business, due_on: due_on)

    if payable_debt.blank? || receivable_debt.blank?
      @purchase_invoice.errors.add(:base, 'No se pudo crear la deuda espejo interempresa al actualizar la factura.')
      return
    end

    ensure_intercompany_isolated_group_tokens!(
      invoice: invoice,
      payable_debt: payable_debt,
      receivable_debt: receivable_debt,
    )
    return if @purchase_invoice.errors.any?

    payable_debt.update!(
      amount: (pending_amount_usd + payable_debt.paid_amount.to_d.round(2)).round(2),
      currency: 'USD',
      acreedor: source_business.name,
      due_on: due_on.presence || payable_debt.due_on,
      mirror_sync_enabled: true,
      mirror_debt: receivable_debt,
    )

    receivable_debt.update!(
      amount: (pending_amount_usd + receivable_debt.paid_amount.to_d.round(2)).round(2),
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
      acreedor: source_business.name,
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

  def log_intercompany_update_failure!(stage:)
    return unless @purchase_invoice

    Rails.logger.warn(
      "[INTERCOMPANY_INVOICE_UPDATE_FAILED] " \
      "stage=#{stage} invoice_id=#{@purchase_invoice.id} " \
      "business_id=#{current_business&.id} source_business_id=#{@purchase_invoice.source_business_id} " \
      "errors=#{@purchase_invoice.errors.full_messages.join(' | ')}"
    )
  end

  def log_intercompany_update_exception!(error)
    invoice_id = @purchase_invoice&.id
    Rails.logger.error(
      "[INTERCOMPANY_INVOICE_UPDATE_EXCEPTION] " \
      "invoice_id=#{invoice_id} business_id=#{current_business&.id} " \
      "error_class=#{error.class} error_message=#{error.message}"
    )
    Rails.logger.error(error.backtrace.first(15).join("\n")) if error.backtrace.present?
  end

  def ensure_intercompany_isolated_group_tokens!(invoice:, payable_debt:, receivable_debt:)
    isolated_token = intercompany_isolated_group_token_for(invoice)
    return if isolated_token.blank?

    payable_debt.update!(group_token: isolated_token) if payable_debt.present? && payable_debt.group_token.to_s.strip != isolated_token
    receivable_debt.update!(group_token: isolated_token) if receivable_debt.present? && receivable_debt.group_token.to_s.strip != isolated_token
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
  end

  def intercompany_isolated_group_token_for(invoice)
    invoice_id = invoice&.id.to_i
    return nil unless invoice_id.positive?

    "ic-factura-#{invoice_id}"
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

    if destination_product.blank?
      destination_product = find_existing_destination_product_for_source(
        source_product: source_product,
        source_business: source_business,
      )
      if destination_product.present? && (destination_product.source_business_id.blank? || destination_product.source_product_id.blank?)
        destination_product.update_columns(
          source_business_id: source_business.id,
          source_product_id: source_product.id,
          updated_at: Time.current,
        )
      end
    end

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

    source_variation_attributes = source_product.product_variations.order(:id).map do |variation|
      {
        description: variation.description,
        safety_stock: variation.safety_stock,
      }
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
      product_variations_attributes: source_variation_attributes,
    )

    if source_product.foto.attached? && !destination_product.foto.attached?
      destination_product.foto.attach(source_product.foto.blob)
    end

    destination_product
  rescue ActiveRecord::RecordInvalid => e
    @purchase_invoice.errors.add(:base, e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    nil
  end

  def find_existing_destination_product_for_source(source_product:, source_business:)
    normalized_description = source_product.descripcion.to_s.strip.downcase
    return nil if normalized_description.blank?

    scope = current_business.productos
                            .where('LOWER(TRIM(productos.descripcion)) = ?', normalized_description)
                            .where(presentation: source_product.presentation)

    scope = scope.where(cant_presentation: source_product.cant_presentation) if source_product.pack?

    candidates = scope.to_a
    return nil if candidates.empty?

    candidates.find do |candidate|
      same_mapping = candidate.source_business_id == source_business.id && candidate.source_product_id == source_product.id
      unmapped = candidate.source_business_id.blank? && candidate.source_product_id.blank?
      same_mapping || unmapped
    end
  end

  def normalize_intercompany_item_variation_breakdown!(item:, source_product:, destination_product:)
    source_variations = source_product.product_variations.order(:id).to_a
    destination_by_desc = destination_product.product_variations.order(:id).index_by do |variation|
      variation.description.to_s.strip.downcase
    end

    rows = normalized_item_variation_rows(item)
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
      requested_units = item.unid_x_pack.to_d.positive? ? item.unid_x_pack.to_d : item.cantidad.to_d
      if destination_variation.present? && requested_units.positive?
        normalized_rows = [{
          'variation_id' => destination_variation.id,
          'description' => destination_variation.description,
          'quantity' => requested_units.to_f,
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
    raw_rows = normalized_item_variation_rows(item)

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

  def normalized_item_variation_rows(item)
    raw_breakdown = item.variation_breakdown

    parsed = case raw_breakdown
             when String
               begin
                 JSON.parse(raw_breakdown)
               rescue StandardError
                 []
               end
             when ActionController::Parameters
               raw_breakdown.to_unsafe_h.sort_by { |key, _| key.to_i }.map { |_, value| value }
             when Hash
               raw_breakdown.sort_by { |key, _| key.to_i }.map { |_, value| value }
             when Array
               raw_breakdown
             else
               []
             end

    parsed.select { |entry| entry.is_a?(Hash) }
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
