class DebtsController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:deudas) }
  before_action :ensure_can_create_debt!, only: %i[new create prepare_group]
  before_action :ensure_can_edit_debt!, only: %i[edit update]
  before_action :ensure_can_destroy_debt!, only: %i[destroy hide_paid_group]
  before_action :set_debt, only: %i[show edit update destroy]
  before_action :load_parties, only: %i[new create edit update]
  before_action :load_accounts, only: %i[new create edit update]
  before_action :load_currency_rates, only: %i[new create edit update]

  def index
    @search_query = params[:q].to_s.strip

    scope = current_business
            .debts
            .excluding_service_cost_records
          .includes(:cliente, :debt_payments, :venta)

    if @search_query.present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@search_query)}%"
      scope = scope.left_outer_joins(:cliente).where('clientes.name ILIKE ?', query)
    end

    all_debts = sort_debts(scope.to_a)
    all_receivable_debts = all_debts.select(&:receivable?)
    all_payable_debts = all_debts.select(&:payable?)
    pending_individual_debts = all_debts.select { |debt| debt.balance.to_d > 0.01.to_d }
    pending_receivable_individual_debts = pending_individual_debts.select(&:receivable?)
    pending_payable_individual_debts = pending_individual_debts.select(&:payable?)

    all_collapsed_debts = collapse_grouped_debts(all_debts)
    @collapsed_group_keys = all_collapsed_debts.each_with_object({}) do |debt, hash|
      hash[debt.id] = collapsed_group_key(debt)
    end
    hidden_paid_group_keys = current_business.hidden_debt_groups.pluck(:group_key)
    @has_any_debts = all_collapsed_debts.any?

    @debts = all_collapsed_debts.select { |debt| debt_pending_for_index?(debt) }
    @receivable_debts = @debts.select(&:receivable?)
    @payable_debts = @debts.select(&:payable?)
    @receivable_paid_debts = all_collapsed_debts.select(&:receivable?).reject { |debt| debt_pending_for_index?(debt) }
    @payable_paid_debts = all_collapsed_debts.select(&:payable?).reject { |debt| debt_pending_for_index?(debt) }
    @receivable_paid_debts = @receivable_paid_debts.reject do |debt|
      hidden_paid_group_keys.include?(@collapsed_group_keys[debt.id])
    end
    @payable_paid_debts = @payable_paid_debts.reject do |debt|
      hidden_paid_group_keys.include?(@collapsed_group_keys[debt.id])
    end
    @receivable_groups = build_cliente_groups(@receivable_debts, sort: :cliente_name_asc)
    @receivable_groups = prioritize_cashea_group_first(@receivable_groups)
    @payable_groups = build_cliente_groups(@payable_debts)
    @receivable_paid_groups = build_cliente_groups(@receivable_paid_debts, sort: :paid_recent_desc)
    @payable_paid_groups = build_cliente_groups(@payable_paid_debts)
    @receivable_group_totals = build_group_totals(@receivable_groups)
    @payable_group_totals = build_group_totals(@payable_groups)
    @receivable_paid_group_totals = build_group_totals(@receivable_paid_groups)
    @payable_paid_group_totals = build_group_totals(@payable_paid_groups)

    @receivable_count = count_debt_groups(@receivable_groups)
    @payable_count = count_debt_groups(@payable_groups)
    @receivable_paid_count = @receivable_paid_debts.size
    @payable_paid_count = @payable_paid_debts.size
    receivable_overdue_debts = all_receivable_debts.select(&:overdue?)
    payable_overdue_debts = all_payable_debts.select(&:overdue?)
    @receivable_overdue_count = receivable_overdue_debts.size
    @payable_overdue_count = payable_overdue_debts.size
    @receivable_overdue_total_usd_bcv = total_usd_balance(receivable_overdue_debts)
    @payable_overdue_total_usd_bcv = total_usd_balance(payable_overdue_debts)
    @receivable_total_usd_bcv = total_usd_balance(all_receivable_debts)
    @payable_total_usd_bcv = total_usd_balance(all_payable_debts)
    @overdue_count = receivable_overdue_debts.size + payable_overdue_debts.size
    @receivable_next_due_on = closest_due_on(pending_receivable_individual_debts)
    @payable_next_due_on = closest_due_on(pending_payable_individual_debts)
    @next_due_on = closest_due_on(pending_individual_debts)
    @search_pending_count = @debts.count
    @search_paid_count = @receivable_paid_count + @payable_paid_count
    @group_setup_clientes = current_business.clientes.order(:name)
    @group_setup_currency_options = allowed_group_currency_codes
    @cashea_banner_url = cashea_banner_url_for_admin
  end

  def hide_paid_group
    group_key = params[:group_key].to_s.strip

    if group_key.blank?
      redirect_to debts_path, alert: 'No se pudo ocultar el conjunto pagado seleccionado.'
      return
    end

    current_business.hidden_debt_groups.find_or_create_by!(group_key: group_key)
    redirect_to debts_path, notice: 'Conjunto pagado ocultado del listado.'
  rescue ActiveRecord::RecordInvalid
    redirect_to debts_path, alert: 'No se pudo ocultar el conjunto pagado seleccionado.'
  end

  def prepare_group
    cliente_id = params[:cliente_id].presence
    currency = params[:currency].to_s.upcase.presence || 'USD'

    if cliente_id.blank?
      redirect_to debts_path, notice: 'Debes seleccionar un cliente para crear o abrir un grupo de deudas.'
      return
    end

    if blocked_group_currency?(currency)
      redirect_to debts_path, notice: 'La moneda del grupo no puede ser VES ni Unidad VI.'
      return
    end

    unless allowed_group_currency_codes.include?(currency)
      redirect_to debts_path, notice: 'La moneda seleccionada no tiene una tasa registrada disponible para trabajar deudas.'
      return
    end

    active_group_debts = active_receivable_group_debts(cliente_id: cliente_id, currency: currency)

    if active_group_debts.any?
      target_debt = active_group_debts.first
      redirect_to debt_path(target_debt, group_currency: currency, group_cliente_id: cliente_id, only_active: 1,
                                         group_token: debt_group_token(target_debt))
      return
    end

    @debt = current_business.debts.new(
      debt_kind: 'receivable',
      issued_on: Date.current,
      cliente_id: cliente_id,
      currency: currency
    )

    @grouped_debts = []
    @show_group_currency = currency
    @payments = []
    @show_total_amount_usd_bcv = 0.to_d
    @show_total_paid_usd_bcv = 0.to_d
    @show_total_balance_usd_bcv = 0.to_d
    @show_last_payment_at = nil
    @show_overdue_count = 0
    @show_payment_rows = []
    @show_debt_rows = []

    @loan_accounts = loan_accounts_for_group_currency(currency)
    @show_currency_options = [currency]

    render :show
  end

  def new
    # Lógica de agrupación automática
    cliente_id = params[:cliente_id]
    moneda = params[:currency] || 'USD'
    es_usdt = moneda.to_s.upcase == 'USDT'
    scope = current_business.debts.where(debt_kind: 'receivable')
    scope = scope.where(cliente_id: cliente_id) if cliente_id.present?
    scope = scope.where(currency: moneda)
    scope = scope.excluding_service_cost_records
    scope = scope.includes(:debt_payments)

    # Buscar grupo activo (no saldado)
    grupo_activo = nil
    unless es_usdt
      scope.group_by { |d| d.group_root_debt_id || d.id }.each do |root_id, deudas|
        saldo_total = deudas.sum { |d| d.balance }
        if saldo_total > 0.01
          grupo_activo = deudas
          break
        end
      end
    end

    if grupo_activo.present?
      # Usar el grupo activo existente
      @debt = grupo_activo.first
      @debt_entries_form = grupo_activo.map { |debt| debt_entry_from_record(debt) }
    else
      # Crear nuevo grupo
      @debt = current_business.debts.new(
        debt_kind: 'receivable',
        issued_on: Date.current,
        cliente_id: cliente_id,
        currency: moneda
      )
      @debt_entries_form = [default_debt_entry]
    end
  end

  def create
    @debt_entries_form = debt_entries_form_params
    normalized_entries = normalized_debt_entries
    shared_attrs = shared_debt_params
    @debt = current_business.debts.new(shared_attrs)

    if shared_attrs[:cliente_id].blank?
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, 'Debes seleccionar un cliente para registrar la deuda.')
      render :new, status: :unprocessable_entity
      return
    end

    if normalized_entries.any? { |entry| blocked_group_currency?(entry[:currency]) }
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, 'No puedes registrar deudas en VES ni en Unidad VI como moneda del grupo.')
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence)
      return
    end

    if normalized_entries.any? { |entry| !allowed_group_currency_codes.include?(entry[:currency].to_s.upcase) }
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, 'La moneda seleccionada no tiene una tasa registrada disponible para registrar la deuda.')
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence)
      return
    end

    conversion_ok = convert_entry_amounts_to_group_currency!(normalized_entries)
    unless conversion_ok
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence)
      return
    end

    if params[:edit_debt_id].present?
      handle_inline_edit_from_show(normalized_entries, shared_attrs)
      return
    end

    if normalized_entries.empty?
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, 'Debes agregar al menos una deuda con monto, moneda y fecha de emision.')
      render :new, status: :unprocessable_entity
      return
    end

    # Buscar grupo activo (no saldado) para el cliente y moneda.
    cliente_id = shared_attrs[:cliente_id]
    moneda = normalized_entries.first&.dig(:currency).presence || 'USD'
    active_group_debts = active_receivable_group_debts(cliente_id: cliente_id, currency: moneda)
    group_token = active_group_debts.any? ? debt_group_token(active_group_debts.first) : generate_debt_group_token

    debts_to_create = normalized_entries.each_with_index.map do |entry, index|
      attrs = shared_attrs.merge(debt_attributes_from_entry(entry))
      attrs[:name] = debt_name_for_entry(index, entry[:description])
      attrs[:group_token] = group_token if Debt.column_names.include?('group_token')
      current_business.debts.new(attrs)
    end

    @debt = debts_to_create.first

    invalid_rows = false
    debts_to_create.each_with_index do |debt, index|
      next if debt.valid?

      invalid_rows = true
      debt.errors.full_messages.each do |message|
        @debt.errors.add(:base, "Deuda #{index + 1}: #{message}")
      end
    end

    invalid_rows = true unless validate_loan_entries(normalized_entries, shared_attrs[:debt_kind])

    if invalid_rows
      render :new, status: :unprocessable_entity
      return
    end

    success = false
    Debt.transaction do
      debts_to_create.each(&:save!)

      success = record_loan_disbursements(debts_to_create, normalized_entries)
      raise ActiveRecord::Rollback unless success

      if register_payment_now?
        success = record_initial_payments(debts_to_create)
        raise ActiveRecord::Rollback unless success
      else
        success = true
      end
    end

    if success
      notice = debts_to_create.size == 1 ? 'Deuda creada exitosamente.' : "#{debts_to_create.size} deudas creadas exitosamente."
      redirect_to_show_or_index(notice: notice, fallback_debt: debts_to_create.first)
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @debt = group_root_for(@debt)
    grouped_debts = debts_for_show(@debt)
    @grouped_debts = sort_debts(grouped_debts).uniq { |item| item.id }
    @show_group_currency = params[:group_currency].to_s.upcase.presence || @debt.currency.to_s.upcase

    @payments = DebtPayment
                .where(debt_id: @grouped_debts.map(&:id))
                .includes(:account, :debt)
                .order(occurred_at: :desc, created_at: :desc)

    @show_total_amount_usd_bcv = total_usd_amount(@grouped_debts)
    @show_total_paid_usd_bcv = total_usd_paid_for_debts(@grouped_debts)
    @show_total_balance_usd_bcv = total_usd_balance_for_card(@grouped_debts)
    @show_total_balance_ves_for_usd_group = if @show_group_currency == 'USD'
                                              conversion = CurrencyConverter.convert(
                                                amount: @show_total_balance_usd_bcv,
                                                from_currency: 'USD',
                                                to_currency: 'VES',
                                                on_date: Date.current
                                              )
                                              conversion&.dig(:amount).to_d.round(2)
                                            else
                                              0.to_d
                                            end
    @show_last_payment_at = @payments.first&.occurred_at
    @show_last_activity_at = group_last_activity_at_for(@grouped_debts)
    @show_overdue_count = @grouped_debts.count(&:overdue?)
    @can_register_group_payment = current_user_admin? || current_user_manager?

    @show_payment_rows = @payments.map do |payment|
      shift = cash_shift_for_payment(payment)
      closed_shift = shift&.closed?
      delete_allowed = current_user_admin? || shift&.open?
      delete_block_reason = if closed_shift && !current_user_admin?
                              'Este pago pertenece a un turno ya cerrado. Solo el administrador puede eliminarlo.'
                            elsif shift.nil? && !current_user_admin?
                              'No se pudo determinar un turno abierto para este pago. Solo el administrador puede eliminarlo.'
                            end

      {
        payment: payment,
        equivalent_usd_bcv: payment_amount_usd_bcv(payment),
        debt_label: payment.excess_payment? ? 'Excedente' : (payment.debt&.description.to_s.strip.presence || 'Deuda sin descripcion'),
        delete_allowed: delete_allowed,
        delete_warning: closed_shift,
        delete_block_reason: delete_block_reason,
      }
    end

    @show_debt_rows = @grouped_debts.map do |debt|
      loan_movement = original_loan_account_movement_for_debt(debt)
      loan_account = loan_movement&.account

      {
        debt: debt,
        amount_usd_bcv: amount_in_usd_bcv_for_debt(debt.amount.to_d, debt),
        paid_usd_bcv: paid_amount_usd_bcv_for_debt(debt),
        balance_usd_bcv: real_balance_usd_bcv_for_debt(debt),
        loan_enabled: loan_movement.present?,
        loan_account_id: loan_movement&.account_id,
        loan_account_name: loan_account&.name,
        loan_account_currency: loan_account&.currency,
        loan_amount: loan_movement&.amount.to_d
      }
    end

    @intercompany_group_payment_mode = intercompany_group_payment_mode?(@grouped_debts)
    @intercompany_mirror_business = intercompany_mirror_business_for(@grouped_debts)
    @payment_accounts = payment_accounts_for_group_currency(
      @show_group_currency,
      include_inactive_fallback: @intercompany_group_payment_mode
    )
    @intercompany_mirror_accounts = intercompany_mirror_accounts_for(@intercompany_mirror_business)
    @currency_rates_to_ves = @payment_accounts.map(&:currency).uniq.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: Date.current).to_d.to_f
    end
    @currency_rates_to_ves['USD'] ||= CurrencyConverter.rate_to_ves('USD', on_date: Date.current).to_d.to_f
    @currency_rates_to_ves['VES'] = 1.0

    @loan_accounts = loan_accounts_for_group_currency(@show_group_currency)
    @show_currency_options = [@show_group_currency]
  end

  def edit
    redirect_to debt_path(@debt), notice: 'La edicion desde esta vista ya no esta disponible.'
  end

  def update
    @debt = group_root_for(@debt)
    @debt_entries_form = debt_entries_form_params
    normalized_entries = normalized_debt_entries
    shared_attrs = shared_debt_params

    if normalized_entries.empty?
      @debt.errors.add(:base, 'Debes agregar al menos una deuda con monto, moneda y fecha de emision.')
      redirect_to debt_path(@debt), notice: @debt.errors.full_messages.to_sentence
      return
    end

    existing_group_debts = editable_active_debts_for(@debt)
    existing_by_id = existing_group_debts.index_by(&:id)
    grouped_after_update = normalized_entries.size > 1
    group_name = grouped_debt_name(
      @debt.display_name,
      @debt.id,
      grouped_after_update
    )

    debts_to_save = normalized_entries.each_with_index.map do |entry, index|
      debt = existing_by_id[entry[:debt_id].to_i] || current_business.debts.new

      if debt.venta_id.present?
        # Las deudas provenientes de ventas no se editan desde deudas.
        debt.assign_attributes(shared_attrs.merge(
          amount: debt.amount,
          currency: debt.currency,
          issued_on: debt.issued_on,
          due_on: debt.due_on,
          description: debt.description
        ))
      else
        debt.assign_attributes(shared_attrs.merge(debt_attributes_from_entry(entry)))
      end

      debt.name = group_name
      if debt.respond_to?(:group_token) && @debt.respond_to?(:group_token)
        debt.group_token ||= @debt.group_token.presence || debt_group_token(@debt)
      end
      debt
    end

    submitted_ids = normalized_entries.map { |entry| entry[:debt_id].to_i }.select(&:positive?)
    debts_to_remove = existing_group_debts.reject { |debt| submitted_ids.include?(debt.id) }
    @debt = debts_to_save.first

    invalid_rows = false

    debts_to_save.each_with_index do |debt, index|
      next if debt.valid?

      invalid_rows = true
      debt.errors.full_messages.each do |message|
        @debt.errors.add(:base, "Deuda #{index + 1}: #{message}")
      end
    end

    debts_to_remove.each_with_index do |debt, index|
      if debt.venta_id.present?
        invalid_rows = true
        @debt.errors.add(:base,
                         "No puedes eliminar la deuda #{normalized_entries.size + index + 1} porque proviene de una venta.")
        next
      end

      next unless debt.debt_payments.exists?

      invalid_rows = true
      @debt.errors.add(:base,
                       "No puedes eliminar la deuda #{normalized_entries.size + index + 1} porque tiene pagos registrados.")
    end

    invalid_rows = true unless validate_loan_entries(normalized_entries, shared_attrs[:debt_kind])

    if invalid_rows
      redirect_to debt_path(@debt), notice: @debt.errors.full_messages.to_sentence
      return
    end

    success = false

    Debt.transaction do
      debts_to_save.each(&:save!)
      debts_to_remove.each(&:destroy!)

      success = record_loan_disbursements(debts_to_save, normalized_entries)
      raise ActiveRecord::Rollback unless success

      if register_payment_now?
        success = record_initial_payments(debts_to_save)
        raise ActiveRecord::Rollback unless success
      else
        success = true
      end
    end

    if success
      notice = if debts_to_save.size > 1
                 "Deuda actualizada. El registro ahora tiene #{debts_to_save.size} deudas asociadas."
               else
                 'Deuda actualizada exitosamente.'
               end

      redirect_to debts_path, notice: notice
    else
      redirect_to debt_path(@debt), notice: @debt.errors.full_messages.to_sentence.presence || 'No se pudo actualizar la deuda.'
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to debt_path(@debt), notice: @debt.errors.full_messages.to_sentence.presence || 'No se pudo actualizar la deuda.'
  end

  def destroy
    original_debt = @debt
    grouped_debts = debts_in_same_edit_group(group_root_for(@debt))
    delete_group = params[:delete_scope].to_s == 'group'
    debts_to_delete = delete_group ? grouped_debts : [original_debt]
    remove_movements = params[:delete_mode].to_s == 'with_movements'
    movements_to_remove = remove_movements ? linked_account_movements_for_debts(debts_to_delete) : []

    Debt.transaction do
      movements_to_remove.each(&:destroy!)
      debts_to_delete.each(&:destroy!)
    end

    notice = debts_to_delete.size > 1 ? "#{debts_to_delete.size} deudas eliminadas." : 'Deuda eliminada.'
    notice = if remove_movements
               "#{notice} #{movements_to_remove.size} movimientos de cuenta eliminados."
             else
               "#{notice} Los movimientos en cuentas se conservaron."
             end

    redirect_after_debt_destroy(notice: notice, delete_group: delete_group)
  end

  def create_cliente
    cliente = current_business.clientes.new(quick_cliente_params)
    cliente.document_type = 'V' if cliente.document_type.blank?

    if cliente.phone.blank?
      render json: { error: 'El telefono es obligatorio.' }, status: :unprocessable_entity
      return
    end

    if cliente.save
      render json: {
        id: cliente.id,
        name: cliente.name,
        document: cliente.document_label,
        phone: cliente.phone
      }, status: :created
    else
      render json: { error: cliente.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def ensure_can_create_debt!
    return if can_manage_action?(:create_debt)

    deny_access('No tienes permiso para crear deudas.')
  end

  def ensure_can_edit_debt!
    return if can_manage_action?(:edit_debt)

    deny_access('No tienes permiso para editar deudas.')
  end

  def ensure_can_destroy_debt!
    return if can_manage_action?(:destroy_debt)

    deny_access('No tienes permiso para eliminar deudas.')
  end

  def set_debt
    @debt = current_business.debts.excluding_service_cost_records.find(params[:id])
  end

  def load_parties
    @clientes = current_business.clientes.order(:name)
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).where.not(account_type: 'cashea').order(:name)
  end

  def load_currency_rates
    @currency_rates_to_ves = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency).to_d.to_f
    end
    @currency_rates_to_ves['VES'] = 1.0
  end

  def debt_params
    params.require(:debt).permit(
      :name,
      :description,
      :debt_kind,
      :amount,
      :currency,
      :issued_on,
      :due_on,
      :cliente_id
    )
  end

  def shared_debt_params
    params.require(:debt).permit(
      :debt_kind,
      :cliente_id
    )
  end

  def debt_entries_form_params
    rows = raw_debt_entry_rows.map do |row|
      next if row.blank?

      amount = row_value(row, :amount)
      currency = row_value(row, :currency)
      issued_on = row_value(row, :issued_on)
      due_on = row_value(row, :due_on)
      description = row_value(row, :description)
      debt_id = row_value(row, :debt_id)
      venta_id = row_value(row, :venta_id)
      loan_enabled = row_value(row, :loan_enabled)
      loan_account_id = row_value(row, :loan_account_id)
      amount_input_currency = row_value(row, :amount_input_currency)
      next if [amount, currency, issued_on, due_on].all?(&:blank?)

      {
        amount: amount,
        currency: currency,
        issued_on: issued_on,
        due_on: due_on,
        description: description,
        debt_id: debt_id,
        venta_id: venta_id,
        loan_enabled: loan_enabled,
        loan_account_id: loan_account_id,
        amount_input_currency: amount_input_currency
      }
    end.compact

    return [default_debt_entry] if rows.empty?

    rows
  end

  def handle_inline_edit_from_show(normalized_entries, shared_attrs)
    edit_debt_id = params[:edit_debt_id].to_i
    editable_debt = current_business.debts.excluding_service_cost_records.find_by(id: edit_debt_id)

    if editable_debt.blank?
      redirect_to_show_or_index(notice: 'No se encontro la deuda a editar.')
      return
    end

    if editable_debt.venta_id.present?
      redirect_to_show_or_index(notice: 'Las deudas provenientes de ventas no se editan desde este formulario.', fallback_debt: editable_debt)
      return
    end

    entry = normalized_entries.first
    if entry.blank?
      @debt = editable_debt
      @debt.errors.add(:base, 'Debes completar los datos de la deuda para editarla.')
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence, fallback_debt: editable_debt)
      return
    end

    @debt = editable_debt
    @debt.assign_attributes(shared_attrs.merge(debt_attributes_from_entry(entry)))

    invalid_rows = false
    unless @debt.valid?
      invalid_rows = true
      @debt.errors.full_messages.each { |message| @debt.errors.add(:base, message) }
    end

    invalid_rows = true unless validate_loan_entries([entry], shared_attrs[:debt_kind])

    if invalid_rows
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence, fallback_debt: @debt)
      return
    end

    success = false
    Debt.transaction do
      @debt.save!
      success = record_loan_disbursements([@debt], [entry])
      raise ActiveRecord::Rollback unless success
    end

    if success
      redirect_to_show_or_index(notice: 'Deuda actualizada exitosamente.', fallback_debt: @debt)
    else
      redirect_to_show_or_index(notice: @debt.errors.full_messages.to_sentence, fallback_debt: @debt)
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to_show_or_index(notice: 'No se pudo actualizar la deuda.', fallback_debt: editable_debt)
  end

  def redirect_to_show_or_index(notice:, fallback_debt: nil)
    if params[:return_to_debt_id].present?
      return_debt = current_business.debts.excluding_service_cost_records.find_by(id: params[:return_to_debt_id])
      return_debt ||= fallback_debt

      if return_debt.present?
        return_params = {}
        return_params[:group_currency] = params[:return_group_currency] if params[:return_group_currency].present?
        return_params[:group_cliente_id] = params[:return_group_cliente_id] if params[:return_group_cliente_id].present?
        return_params[:only_active] = params[:return_only_active] if params[:return_only_active].present?
        return_params[:group_token] = params[:return_group_token] if params[:return_group_token].present?
        redirect_to debt_path(return_debt, return_params), notice: notice
        return
      end
    end

    if params[:return_group_currency].present? && params[:return_group_cliente_id].present?
      if fallback_debt.present?
        return_params = {
          group_currency: params[:return_group_currency],
          group_cliente_id: params[:return_group_cliente_id],
          only_active: params[:return_only_active].presence || 1,
          group_token: params[:return_group_token].presence
        }
        redirect_to debt_path(fallback_debt, return_params), notice: notice
        return
      end

      redirect_to prepare_group_debts_path(
        cliente_id: params[:return_group_cliente_id],
        currency: params[:return_group_currency]
      ), notice: notice
      return
    end

    redirect_to debts_path, notice: notice
  end

  def active_receivable_group_debts(cliente_id:, currency:)
      currencies = group_scope_currencies_for(currency: currency, debt_kind: 'receivable')

    scope = current_business
            .debts
            .excluding_service_cost_records
        .where(debt_kind: 'receivable', currency: currencies)
            .where(cliente_id: cliente_id)
            .includes(:debt_payments)

    active = scope.select { |debt| debt.balance.to_d > 0.01.to_d }
    return [] if active.empty?

    grouped = active.group_by { |debt| debt_group_token(debt) }
    selected = grouped.max_by do |_token, debts|
      debts.map { |debt| debt.issued_on || debt.created_at&.to_date || Date.new(1970, 1, 1) }.max
    end

    selected ? selected.last : []
  end

  def normalized_debt_entries
    debt_entries_form_params.map do |row|
      debt_id = row[:debt_id].to_i
      {
        amount: parse_decimal(row[:amount]),
        currency: row[:currency].to_s.strip.upcase,
        amount_input_currency: row[:amount_input_currency].to_s.strip.upcase,
        issued_on: resolved_issued_on_for_current_user(
          raw_issued_on: row[:issued_on],
          debt_id: debt_id,
        ),
        due_on: parse_debt_date(row[:due_on]),
        description: row[:description].to_s.strip.presence,
        debt_id: debt_id,
        venta_id: row[:venta_id].to_i,
        loan_enabled: loan_enabled_for_current_user?(row[:loan_enabled]),
        loan_account_id: loan_enabled_for_current_user?(row[:loan_enabled]) ? row[:loan_account_id].presence : nil
      }
    end
  end

  def raw_debt_entry_rows
    raw = params[:debt_entries]

    rows = case raw
           when ActionController::Parameters
             raw.to_unsafe_h.sort_by { |key, _| key.to_i }.map { |_, value| value }
           when Hash
             raw.sort_by { |key, _| key.to_i }.map { |_, value| value }
           when Array
             raw
           else
             []
           end

    return rows if rows.present?

    legacy_row = {
      amount: params.dig(:debt, :amount),
      currency: params.dig(:debt, :currency),
      issued_on: params.dig(:debt, :issued_on),
      due_on: params.dig(:debt, :due_on),
      description: params.dig(:debt, :description)
    }

    if legacy_row.values.any?(&:present?)
      [legacy_row]
    else
      []
    end
  end

  def row_value(row, key)
    return '' if row.blank?

    row_hash = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
    row_hash[key].presence || row_hash[key.to_s].presence || ''
  end

  def default_debt_entry
    {
      amount: '0',
      currency: 'USD',
      amount_input_currency: 'USD',
      issued_on: Date.current.strftime('%d-%m-%Y'),
      due_on: '',
      description: '',
      loan_enabled: false,
      loan_account_id: ''
    }
  end

  def debt_entry_from_record(debt)
    loan_movement = original_loan_account_movement_for_debt(debt)

    {
      debt_id: debt.id,
      venta_id: debt.venta_id,
      amount: debt.amount.to_d,
      currency: debt.currency,
      issued_on: (debt.issued_on || Date.current).strftime('%d-%m-%Y'),
      due_on: debt.due_on&.strftime('%d-%m-%Y'),
      description: debt.description,
      loan_enabled: loan_movement.present?,
      loan_account_id: loan_movement&.account_id
    }
  end

  def editable_active_debts_for(debt)
    scope = current_business.debts.where(debt_kind: debt.debt_kind)
    scope = scope.where(cliente_id: debt.cliente_id) if debt.cliente_id.present?
    scope = scope.where(currency: debt.currency)
    scope = scope.excluding_service_cost_records.includes(:debt_payments)

    debts = debt.currency.to_s.upcase == 'USDT' ? scope.to_a : scope.select { |item| item.balance > 0.01 }
    sort_debts(debts)
  end

  def debt_attributes_from_entry(entry)
    entry.slice(:amount, :currency, :issued_on, :due_on, :description)
  end

  def debt_name_for_entry(index, description)
    return description.to_s.strip.first(80) if description.present?

    "Deuda #{index + 1}"
  end

  def register_payment_now?
    params[:register_payment].to_s == '1'
  end

  def payment_params
    params.permit(:payment_account_id, :payment_currency, :payment_amount, :payment_method, :payment_reference,
                  :payment_occurred_on)
  end

  def record_initial_payments(debts)
    account = current_business.accounts.find_by(id: payment_params[:payment_account_id])
    payment_currency = payment_params[:payment_currency].presence || account&.currency
    amount = parse_decimal(payment_params[:payment_amount])

    if account.nil? || amount <= 0 || payment_currency.blank?
      @debt.errors.add(:base, 'Completa el pago inicial para registrarlo.')
      return false
    end

    if account.account_type == 'cashea'
      @debt.errors.add(:base, 'La cuenta Cashea no puede usarse para registrar cobros/pagos de deudas.')
      return false
    end

    if account.currency != payment_currency
      @debt.errors.add(:base, 'La cuenta debe coincidir con la moneda seleccionada para el pago.')
      return false
    end

    if account.account_type == 'bank_account' && payment_params[:payment_method].blank?
      @debt.errors.add(:base, 'Selecciona el metodo de pago para cuentas bancarias.')
      return false
    end

    if debts.first&.payable? && amount.to_d > account.balance.to_d
      @debt.errors.add(:base, account.insufficient_balance_message(amount))
      return false
    end

    payment_method = payment_params[:payment_method].presence
    reference = payment_params[:payment_reference].presence
    occurred_on = parse_payment_date(payment_params[:payment_occurred_on]) || Date.current
    total_pending = total_balance_in_payment_currency(debts, payment_currency, occurred_on)

    if total_pending <= 0
      @debt.errors.add(:base, 'No hay saldo pendiente para aplicar el pago inicial.')
      return false
    end

    if amount > (total_pending + 0.01.to_d)
      @debt.errors.add(:base, 'El pago inicial excede el saldo pendiente total de las deudas creadas.')
      return false
    end

    remaining_amount = amount.to_d.round(2)
    payments_to_persist = []

    debts.each do |debt|
      break if remaining_amount <= 0

      max_for_debt = max_payment_amount_for_debt(debt, payment_currency, occurred_on)
      next if max_for_debt <= 0

      allocation = [remaining_amount, max_for_debt].min.to_d.round(2)
      next if allocation <= 0

      payment = debt.debt_payments.new(
        account: account,
        amount: allocation,
        currency: payment_currency,
        payment_method: payment_method,
        reference: reference,
        occurred_at: occurred_on
      )

      unless payment.valid?
        payment.errors.full_messages.each { |message| @debt.errors.add(:base, message) }
        return false
      end

      if payment.amount_in_debt_currency > debt.balance
        @debt.errors.add(:base, 'No se pudo distribuir el pago inicial sin exceder el saldo de una deuda.')
        return false
      end

      payments_to_persist << [debt, payment]
      remaining_amount = (remaining_amount - payment.amount.to_d).round(2)
    end

    if payments_to_persist.empty?
      @debt.errors.add(:base, 'No se pudo aplicar el pago inicial a las deudas cargadas.')
      return false
    end

    total_value = amount.to_d.round(2)
    primary_payment = payments_to_persist.first&.last
    primary_payment.movement_amount_override = total_value if primary_payment && total_value.positive?
    payments_to_persist.drop(1).each do |_debt, payment|
      payment.skip_account_movement = true
    end

    payments_to_persist.each do |_debt, payment|
      payment.save!
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @debt.errors.add(:base, e.message)
    false
  end

  def total_balance_in_payment_currency(debts, payment_currency, occurred_on = Date.current)
    debts.sum do |debt|
      conversion = CurrencyConverter.convert(
        amount: debt.balance,
        from_currency: debt.currency,
        to_currency: payment_currency,
        on_date: occurred_on
      )
      conversion&.dig(:amount).to_d
    end
  end

  def max_payment_amount_for_debt(debt, payment_currency, occurred_on = Date.current)
    conversion = CurrencyConverter.convert(
      amount: debt.balance,
      from_currency: debt.currency,
      to_currency: payment_currency,
      on_date: occurred_on
    )
    return 0.to_d if conversion.blank?

    max_amount = conversion[:amount].to_d

    3.times do
      back_conversion = CurrencyConverter.convert(
        amount: max_amount,
        from_currency: payment_currency,
        to_currency: debt.currency,
        on_date: occurred_on
      )

      return max_amount if back_conversion.present? && back_conversion[:amount].to_d <= debt.balance.to_d

      max_amount = (max_amount - 0.01.to_d).round(2)
      break if max_amount <= 0
    end

    max_amount.positive? ? max_amount : 0.to_d
  end

  def validate_loan_entries(entries, _debt_kind)
    if entries.any? { |entry| entry[:loan_enabled] } && !current_user_can_manage_loan_debts?
      @debt.errors.add(:base, 'Solo administrador o encargado puede registrar deudas como prestamo.')
      return false
    end

    valid = true

    entries.each_with_index do |entry, index|
      next unless entry[:loan_enabled]

      account = eligible_loan_accounts_scope.find_by(id: entry[:loan_account_id])

      if account.blank?
        @debt.errors.add(:base, "Deuda #{index + 1}: selecciona la cuenta del prestamo.")
        valid = false
      else
        entry[:loan_account] = account
      end

      debt_amount = entry[:amount].to_d
      debt_currency = entry[:currency].to_s

      unless debt_amount.positive? && debt_currency.present?
        @debt.errors.add(:base,
                         "Deuda #{index + 1}: el monto de la deuda debe ser mayor a cero para registrar el prestamo.")
        valid = false
        next
      end

      next if account.blank?

      if debt_currency.to_s.upcase == 'USDT' && account.currency.to_s.upcase != 'USDT'
        @debt.errors.add(:base,
                         "Deuda #{index + 1}: para deudas en USDT debes seleccionar una cuenta en USDT.")
        valid = false
        next
      end

      if debt_currency.to_s.upcase != 'USDT' && account.currency.to_s.upcase == 'USDT'
        @debt.errors.add(:base,
                         "Deuda #{index + 1}: para deudas no USDT no puedes usar cuentas en USDT.")
        valid = false
        next
      end

      input_amount = entry[:input_amount].to_d
      input_currency = entry[:amount_input_currency].to_s.upcase

      loan_amount = if input_amount.positive? && input_currency == account.currency.to_s.upcase
                      input_amount
                    else
                      conversion = CurrencyConverter.convert(
                        amount: debt_amount,
                        from_currency: debt_currency,
                        to_currency: account.currency
                      )

                      if conversion.blank? || conversion[:amount].to_d <= 0
                        @debt.errors.add(:base,
                                         "Deuda #{index + 1}: no se pudo convertir el monto de la deuda a la moneda de la cuenta seleccionada.")
                        valid = false
                        next
                      end

                      conversion[:amount].to_d
                    end

      if loan_amount > account.balance.to_d
        @debt.errors.add(:base,
                         "Deuda #{index + 1}: #{account.insufficient_balance_message(loan_amount)}")
        valid = false
        next
      end

      entry[:loan_amount] = loan_amount
    end

    valid
  end

  def record_loan_disbursements(debts, entries)
    debts.zip(entries).each_with_index do |(debt, entry), index|
      existing_movements = sorted_loan_account_movements_for_debt(debt)

      unless entry[:loan_enabled]
        existing_movements.each(&:destroy!)
        next
      end

      account = entry[:loan_account] || current_business.accounts.where(active: true).find_by(id: entry[:loan_account_id])
      loan_amount = loan_amount_in_account_currency(entry, account)

      if account.blank? || loan_amount <= 0
        @debt.errors.add(:base, "Deuda #{index + 1}: no se pudo registrar el prestamo asociado.")
        return false
      end

      movement_attrs = {
        movement_kind: loan_movement_kind_for(debt),
        amount: loan_amount,
        description: build_loan_movement_description(debt),
        occurred_at: debt.issued_on || Date.current,
        payment_method: account.account_type == 'bank_account' ? 'transfer' : nil
      }

      primary_movement = existing_movements.first

      if primary_movement.present?
        if primary_movement.account_id == account.id
          primary_movement.update!(movement_attrs)
          existing_movements.drop(1).each(&:destroy!)
        else
          existing_movements.each(&:destroy!)
          account.account_movements.create!(movement_attrs)
        end
      else
        account.account_movements.create!(movement_attrs)
      end
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @debt.errors.add(:base, e.message)
    false
  end

  def build_loan_movement_description(debt)
    debt_description = debt.description.to_s.strip.presence || 'Deuda sin descripcion'
    cliente_name = debt.counterparty_display_name
    actor_name = Current.user&.display_name.to_s.strip.presence || 'Usuario no identificado'
    "Prestamo deuda: #{debt_description} - Cliente: #{cliente_name} - Registrado por: #{actor_name} [DEBT:#{debt.id}] [LOAN_DEBT]"
  end

  def current_user_can_manage_loan_debts?
    current_user_admin? || current_user_manager?
  end

  def loan_enabled_for_current_user?(raw_value)
    return false unless current_user_can_manage_loan_debts?

    ActiveModel::Type::Boolean.new.cast(raw_value)
  end

  def resolved_issued_on_for_current_user(raw_issued_on:, debt_id:)
    parsed_date = parse_debt_date(raw_issued_on)
    return parsed_date if current_user_admin?

    if debt_id.to_i.positive?
      existing_debt = current_business.debts.excluding_service_cost_records.find_by(id: debt_id)
      return existing_debt&.issued_on || Date.current
    end

    Date.current
  end

  def loan_movement_kind_for(debt)
    debt.payable? ? 'income' : 'expense'
  end

  def linked_account_movements_for_debts(debts)
    movements = []

    debts.each do |debt|
      movements.concat(loan_account_movements_for_debt(debt))

      debt.debt_payments.includes(:account).each do |payment|
        movements.concat(payment_account_movements_for(payment))
      end
    end

    movements.compact.uniq { |movement| movement.id }
  end

  def loan_account_movements_for_debt(debt)
    token = "[DEBT:#{debt.id}]"

    business_account_movements_scope
      .where('description ILIKE ?', "%#{token}%")
      .where(movement_kind: loan_movement_kind_for(debt))
      .where("description ILIKE :explicit_tag OR description ILIKE :legacy_prefix", explicit_tag: '%[LOAN_DEBT]%', legacy_prefix: 'Prestamo deuda:%')
      .where('description NOT ILIKE ?', '%[DP:%')
      .to_a
  end

  def sorted_loan_account_movements_for_debt(debt)
    loan_account_movements_for_debt(debt)
      .sort_by do |movement|
        [movement.occurred_at || Date.new(1970, 1, 1), movement.created_at || Time.zone.at(0),
         movement.id.to_i]
    end
      .reverse
  end

  def latest_loan_account_movement_for_debt(debt)
    sorted_loan_account_movements_for_debt(debt).first
  end

  def original_loan_account_movement_for_debt(debt)
    sorted_loan_account_movements_for_debt(debt).last
  end

  def payment_account_movements_for(payment)
    business_account_movements_scope
      .where(account_id: payment.account_id)
      .where('description ILIKE ?', "%[DP:#{payment.id}]%")
      .to_a
  end

  def business_account_movements_scope
    AccountMovement.joins(:account).where(accounts: { business_id: current_business.id })
  end

  def loan_amount_in_account_currency(entry, account)
    return 0.to_d if account.blank?

    cached_amount = entry[:loan_amount].to_d
    return cached_amount if cached_amount.positive?

    conversion = CurrencyConverter.convert(
      amount: entry[:amount].to_d,
      from_currency: entry[:currency],
      to_currency: account.currency
    )

    conversion&.dig(:amount).to_d
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(',', '.')
    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_payment_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, '%d-%m-%Y')
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def parse_debt_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, '%d-%m-%Y')
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def blocked_group_currency?(code)
    normalized = code.to_s.strip.upcase
    return true if normalized == 'VES'
    return true if normalized == 'UVI'

    normalized.include?('UNIDAD VI')
  end

  def allowed_group_currency_codes
    Account::CURRENCIES.keys
      .map { |code| code.to_s.upcase }
      .uniq
      .reject { |code| blocked_group_currency?(code) }
      .select { |code| CurrencyConverter.rate_to_ves(code).to_d.positive? }
  end

  def eligible_loan_accounts_scope
    current_business
      .accounts
      .where(active: true)
      .where.not(account_type: Account::SPECIAL_ACCOUNT_TYPES)
      .where.not("REPLACE(LOWER(name), ' ', '') LIKE ?", '%payall%')
  end

  def loan_accounts_for_group_currency(group_currency)
    scope = eligible_loan_accounts_scope.order(:name)

    if group_currency.to_s.upcase == 'USDT'
      scope.where(currency: 'USDT')
    else
      scope.where.not(currency: 'USDT')
    end
  end

  def payment_accounts_for_group_currency(group_currency, include_inactive_fallback: false)
    base_scope = current_business.accounts
                                 .where.not(account_type: 'cashea')
                                 .where.not("REPLACE(LOWER(name), ' ', '') LIKE ?", '%payall%')

    active_scope = apply_payment_currency_filter(base_scope.where(active: true), group_currency)
    active_accounts = active_scope.order(:currency, :name).to_a
    return active_accounts if active_accounts.any?

    return active_accounts unless include_inactive_fallback

    @using_inactive_payment_accounts = true
    apply_payment_currency_filter(base_scope, group_currency).order(:currency, :name).to_a
  end

  def apply_payment_currency_filter(scope, group_currency)
    if group_currency.to_s.upcase == 'USDT'
      scope.where(currency: 'USDT')
    else
      scope.where(currency: %w[USD VES])
    end
  end

  def intercompany_group_payment_mode?(debts)
    debts.present? && debts.all? { |debt| intercompany_invoice_debt?(debt) }
  end

  def intercompany_invoice_debt?(debt)
    description = debt.description.to_s
    return false unless description.include?('[IC_MIRROR]')

    description.include?('[FACTURA_COMPRA:') || description.include?('[FACTURA_COMPRA_MIRROR:')
  end

  def intercompany_mirror_business_for(debts)
    return nil unless intercompany_group_payment_mode?(debts)

    mirror_businesses = debts.filter_map { |debt| debt.mirror_debt&.business }.uniq { |business| business.id }
    return nil unless mirror_businesses.size == 1

    mirror_businesses.first
  end

  def intercompany_mirror_accounts_for(business)
    return [] if business.blank?

    base_scope = business.accounts
                         .where.not(account_type: 'cashea')
                         .where.not("REPLACE(LOWER(name), ' ', '') LIKE ?", '%payall%')

    active_accounts = base_scope.where(active: true).order(:currency, :name).to_a
    return active_accounts if active_accounts.any?

    @using_inactive_intercompany_mirror_accounts = true
    base_scope.order(:currency, :name).to_a
  end

  def convert_entry_amounts_to_group_currency!(entries)
    valid = true

    entries.each do |entry|
      group_currency = entry[:currency].to_s.upcase
      input_currency = entry[:amount_input_currency].presence || group_currency
      amount = entry[:amount].to_d

      entry[:amount_input_currency] = input_currency
      entry[:input_amount] = amount
      next unless amount.positive?
      next if input_currency == group_currency

      conversion = CurrencyConverter.convert(
        amount: amount,
        from_currency: input_currency,
        to_currency: group_currency,
        on_date: entry[:issued_on] || Date.current
      )

      converted_amount = conversion&.dig(:amount).to_d
      unless converted_amount.positive?
        @debt.errors.add(:base,
                         "No se pudo convertir el monto desde #{input_currency} hacia #{group_currency} para registrar la deuda.")
        valid = false
        next
      end

      entry[:amount] = converted_amount.round(2)
    end

    valid
  end

  def total_usd_balance(debts)
    debts.sum do |debt|
      balance = real_balance_usd_bcv_for_debt(debt)
      balance.positive? ? balance : 0.to_d
    end.round(2)
  end

  def total_usd_amount(debts)
    debts.sum do |debt|
      amount = debt.amount.to_d
      next 0.to_d unless amount.positive? || amount.zero?

      amount_in_usd_bcv_for_debt(amount, debt)
    end.round(2)
  end

  def total_usd_paid_for_debts(debts)
    debts.sum { |debt| paid_amount_usd_bcv_for_debt(debt) }.round(2)
  end

  def total_usd_balance_for_card(debts)
    debts.sum { |debt| real_balance_usd_bcv_for_debt(debt) }.round(2)
  end

  def amount_in_usd_bcv_for_debt(amount, debt)
    value = amount.to_d
    return 0.to_d if value.zero?

    conversion = CurrencyConverter.convert(
      amount: value.abs,
      from_currency: debt.currency,
      to_currency: 'USD',
      on_date: debt_reference_date_for_usd(debt)
    )

    converted_amount = conversion&.dig(:amount).to_d
    value.negative? ? -converted_amount : converted_amount
  end

  def payment_amount_usd_bcv(payment)
    conversion = CurrencyConverter.convert(
      amount: payment.amount.to_d,
      from_currency: payment.currency,
      to_currency: 'USD',
      on_date: payment.occurred_at
    )

    conversion&.dig(:amount).to_d
  end

  def paid_amount_usd_bcv_for_debt(debt)
    payments = if debt.debt_payments.loaded?
                 debt.debt_payments
               else
                 debt.debt_payments.to_a
               end

    payments.sum { |payment| payment_amount_usd_bcv(payment) }.round(2)
  end

  def real_balance_usd_bcv_for_debt(debt)
    (amount_in_usd_bcv_for_debt(debt.amount.to_d, debt) - paid_amount_usd_bcv_for_debt(debt)).round(2)
  end

  def debt_reference_date_for_usd(debt)
    debt.issued_on || debt.venta&.created_at&.to_date || Date.current
  end

  def debt_sort_key(debt)
    issued_on = debt.issued_on || debt.created_at&.to_date || Date.new(1970, 1, 1)
    created_at = debt.created_at || Time.zone.at(0)
    normalized_name = debt.display_name.to_s.strip.downcase
    normalized_cliente = debt.counterparty_display_name.to_s.strip.downcase

    [
      -issued_on.jd,
      -created_at.to_i,
      -debt.id.to_i,
      normalized_name,
      normalized_cliente
    ]
  end

  def sort_debts(debts)
    debts.sort_by { |debt| debt_sort_key(debt) }
  end

  def grouped_debt_name(base_name, root_id, grouped)
    normalized_name = base_name.to_s.strip
    normalized_name = "Deuda #{Date.current.strftime('%d-%m-%Y')}" if normalized_name.blank?
    return normalized_name unless grouped && root_id.present?

    "[GRP:#{root_id}] #{normalized_name}"
  end

  def group_root_for(debt)
    return debt if debt.group_token.present?

    root_id = debt.group_root_debt_id
    return debt if root_id.blank?

    current_business.debts.find_by(id: root_id) || debt
  end

  def debts_in_same_edit_group(debt)
    if debt.group_token.present?
      currencies = group_scope_currencies_for(currency: debt.currency, debt_kind: debt.debt_kind)

      grouped = current_business
                .debts
                .excluding_service_cost_records
                .where(debt_kind: debt.debt_kind, group_token: debt.group_token, currency: currencies)
                .includes(:debt_payments, :venta)

      return grouped.to_a if grouped.exists?
    end

    effective_token = debt_group_token(debt).to_s.strip
    if effective_token.present?
      currencies = group_scope_currencies_for(currency: debt.currency, debt_kind: debt.debt_kind)

      grouped = current_business
                .debts
                .excluding_service_cost_records
                .where(debt_kind: debt.debt_kind, currency: currencies)
      grouped = grouped.where(cliente_id: debt.cliente_id) if debt.cliente_id.present?
      grouped = grouped.where(cliente_id: nil) if debt.cliente_id.blank?

      matched = grouped
                .includes(:debt_payments, :venta)
                .to_a
                .select { |candidate| debt_group_token(candidate).to_s.strip == effective_token }

      return matched if matched.present?
    end

    root_id = debt.group_root_debt_id
    return [debt] if root_id.blank?

    grouped = current_business
              .debts
              .where(cliente_id: debt.cliente_id, debt_kind: debt.debt_kind)
              .includes(:debt_payments, :venta)
              .select { |candidate| candidate.group_root_debt_id == root_id }

    grouped.presence || [debt]
  end

  def debts_for_show(debt)
    token_param = params[:group_token].to_s.strip
    if token_param.present?
      debts = debts_with_effective_group_token(
        debt_kind: debt.debt_kind,
        token: token_param,
        currency: debt.currency,
        cliente_id: debt.cliente_id,
      )
      return debts if debts.present?
    end

    if debt.group_token.present?
      debts = debts_with_effective_group_token(
        debt_kind: debt.debt_kind,
        token: debt.group_token,
        currency: debt.currency,
        cliente_id: debt.cliente_id,
      )
      return debts if debts.present?
    end

    # Sin token explicito no debemos abrir por cliente+moneda, porque mezcla ciclos legacy.
    return debts_in_same_edit_group(debt) if token_param.blank?

    return debts_in_same_edit_group(debt) unless params[:group_currency].present?

    scope = current_business
            .debts
            .excluding_service_cost_records
            .where(debt_kind: debt.debt_kind, currency: params[:group_currency].to_s.upcase)
          .includes(:debt_payments, :venta)

    cliente_param = params[:group_cliente_id].to_s
    if cliente_param == 'none'
      scope = scope.where(cliente_id: nil)
    elsif cliente_param.present?
      scope = scope.where(cliente_id: cliente_param.to_i)
    elsif debt.cliente_id.present?
      scope = scope.where(cliente_id: debt.cliente_id)
    end

    debts = scope.to_a

    debts.presence || debts_in_same_edit_group(debt)
  end

  def collapsed_group_key(debt)
    token = debt.group_token.to_s.strip
    return "token-#{token}" if token.present?

    if debt.grouped_record? && debt.group_root_debt_id.present?
      "group-#{debt.group_root_debt_id}"
    else
      "single-#{debt.id}"
    end
  end

  def debt_group_token(debt)
    token = debt.group_token.to_s.strip
    return token if token.present?

    legacy_group_token_for(debt)
  end

  def debts_with_effective_group_token(debt_kind:, token:, currency: nil, cliente_id: nil)
    effective_token = token.to_s.strip
    return [] if effective_token.blank?

    scope = current_business
            .debts
            .excluding_service_cost_records
            .where(debt_kind: debt_kind)
            .includes(:debt_payments, :venta)

    normalized_currency = currency.to_s.strip.upcase
    if normalized_currency.present?
      scope = scope.where(currency: group_scope_currencies_for(currency: normalized_currency, debt_kind: debt_kind))
    end

    if cliente_id.present?
      scope = scope.where(cliente_id: cliente_id)
    elsif !cliente_id.nil?
      scope = scope.where(cliente_id: nil)
    end

    debts = scope.to_a.select do |candidate|
      debt_group_token(candidate).to_s.strip == effective_token
    end

    sort_debts(debts)
  end

  def redirect_after_debt_destroy(notice:, delete_group:)
    return redirect_to debts_path, notice: notice if delete_group

    show_params = {
      group_currency: params[:group_currency].presence,
      group_cliente_id: params[:group_cliente_id].presence,
      only_active: params[:only_active].presence,
      group_token: params[:group_token].presence
    }.compact

    return redirect_to debts_path, notice: notice if show_params.empty?

    next_debt = debt_for_show_redirect(show_params)
    if next_debt.present?
      redirect_to debt_path(next_debt, show_params), notice: notice
    else
      redirect_to debts_path, notice: notice
    end
  end

  def debt_for_show_redirect(show_params)
    token = show_params[:group_token].to_s.strip
    if token.present?
      return current_business
             .debts
             .excluding_service_cost_records
             .where(group_token: token)
             .order(created_at: :desc, id: :desc)
             .first
    end

    scope = current_business.debts.excluding_service_cost_records

    currency = show_params[:group_currency].to_s.strip.upcase
    if currency.present?
      scope = scope.where(currency: group_scope_currencies_for(currency: currency, debt_kind: @debt&.debt_kind || 'receivable'))
    end

    cliente_param = show_params[:group_cliente_id].to_s
    if cliente_param == 'none'
      scope = scope.where(cliente_id: nil)
    elsif cliente_param.present?
      scope = scope.where(cliente_id: cliente_param.to_i)
    end

    scope.order(created_at: :desc, id: :desc).first
  end

  def legacy_group_token_for(debt)
    root_id = debt.group_root_debt_id
    return "legacy-#{root_id}" if root_id.present?

    "legacy-debt-#{debt.id}"
  end

  def generate_debt_group_token
    "grp_#{SecureRandom.hex(10)}"
  end

  def group_scope_currencies_for(currency:, debt_kind:)
    normalized_currency = currency.to_s.strip.upcase
    return [normalized_currency].reject(&:blank?) if normalized_currency.blank?
    return [normalized_currency] unless debt_kind.to_s == 'receivable'
    return %w[USD VES] if normalized_currency == 'USD'

    [normalized_currency]
  end

  def collapse_grouped_debts(debts)
    collapsed = debts
                .group_by { |debt| collapsed_group_key(debt) }
                .values
                .map do |grouped_debts|
                  sorted_group = sort_debts(grouped_debts)
                  root_id = sorted_group.first.group_root_debt_id

                  representative = if root_id.present?
                                     sorted_group.find { |debt| debt.id == root_id } || sorted_group.first
                                   else
                                     sorted_group.first
                                   end

                  representative.card_total_amount = total_usd_amount(grouped_debts)
                  representative.card_total_balance = total_usd_balance_for_card(grouped_debts)
                  representative.card_currency = card_currency_for_index_group(grouped_debts)
                  grouped_count = grouped_debts.size
                  representative.define_singleton_method(:card_debts_count) { grouped_count }
                  representative.card_description_summary = card_description_summary_for(grouped_debts)
                  last_activity_at = group_last_activity_at_for(grouped_debts)
                  last_payment_at = group_last_payment_at_for(grouped_debts)
                  representative.define_singleton_method(:card_last_activity_at) { last_activity_at }
                  representative.define_singleton_method(:card_last_payment_at) { last_payment_at }
                  representative
    end

    sort_debts(collapsed)
  end

  def card_description_summary_for(debts)
    ordered = debts.sort_by do |debt|
      [debt.created_at || Time.zone.at(0), debt.id.to_i]
    end

    descriptions = ordered.filter_map do |debt|
      debt.description.to_s.strip.presence
    end
    missing_count = ordered.size - descriptions.size

    return descriptions.join(', ') if missing_count <= 0
    return "#{format_missing_description_count(missing_count)}." if descriptions.empty?

    "#{descriptions.join(', ')} y #{format_missing_description_count(missing_count)}."
  end

  def group_last_activity_at_for(debts)
    timestamps = []

    debts.each do |debt|
      timestamps << debt.updated_at if debt.updated_at.present?
      timestamps << debt.created_at if debt.created_at.present?

      payments = debt.debt_payments.loaded? ? debt.debt_payments : debt.debt_payments.to_a
      payments.each do |payment|
        timestamps << payment.updated_at if payment.updated_at.present?
        timestamps << payment.created_at if payment.created_at.present?
      end
    end

    timestamps.compact.max
  end

  def group_last_payment_at_for(debts)
    payment_dates = debts.flat_map do |debt|
      payments = debt.debt_payments.loaded? ? debt.debt_payments : debt.debt_payments.to_a
      payments.map(&:occurred_at)
    end.compact

    payment_dates.max_by { |value| sortable_time_value(value) }
  end

  def cash_shift_for_payment(payment)
    payment_date = payment.occurred_at
    return nil if payment_date.blank?

    current_business
      .cash_shifts
      .order(opened_at: :desc)
      .detect do |shift|
        start_date = shift.opened_at.in_time_zone('America/Caracas').to_date
        end_date = (shift.closed_at || Time.current).in_time_zone('America/Caracas').to_date
        payment_date >= start_date && payment_date <= end_date
      end
  end

  def format_missing_description_count(count)
    count.to_i == 1 ? '1 deuda sin descripcion' : "#{count.to_i} deudas sin descripcion"
  end

  def build_cliente_groups(debts, sort: :default)
    grouped = debts
              .group_by(&:cliente)
              .map { |cliente, cliente_debts| [cliente, sort_debts(cliente_debts)] }

    case sort
    when :cliente_name_asc
      grouped.sort_by do |cliente, _cliente_debts|
        [cliente&.name.to_s.downcase, cliente.present? ? 0 : 1]
      end
    when :paid_recent_desc
      grouped
        .map do |cliente, cliente_debts|
          ordered = cliente_debts.sort_by { |debt| paid_recency_sort_key(debt) }
          [cliente, ordered]
        end
        .sort_by do |cliente, cliente_debts|
          latest_paid_at = cliente_debts.map { |debt| debt_last_payment_at_for_index(debt) }
                                        .compact
                                        .max_by { |value| sortable_time_value(value) }
          [latest_paid_at.present? ? 0 : 1, -sortable_time_value(latest_paid_at), cliente&.name.to_s.downcase]
        end
    else
      grouped.sort_by do |cliente, cliente_debts|
        first_debt = cliente_debts.first
        first_key = first_debt ? debt_sort_key(first_debt) : [0, 0, 0, '', '']
        [first_key[0], first_key[1], cliente&.name.to_s.downcase]
      end
    end
  end

  def debt_last_payment_at_for_index(debt)
    return debt.card_last_payment_at if debt.respond_to?(:card_last_payment_at) && debt.card_last_payment_at.present?

    payments = debt.debt_payments.loaded? ? debt.debt_payments : debt.debt_payments.to_a
    payments.map(&:occurred_at).compact.max
  end

  def paid_recency_sort_key(debt)
    paid_at = debt_last_payment_at_for_index(debt)
    [paid_at.present? ? 0 : 1, -sortable_time_value(paid_at), -(debt.id.to_i)]
  end

  def sortable_time_value(value)
    return 0 if value.blank?

    return value.jd if value.is_a?(Date)
    return value.to_i if value.respond_to?(:to_i)

    value.to_time.to_i
  end

  def build_group_totals(groups)
    groups.each_with_object({}) do |(cliente, debts), totals|
      debts.group_by { |debt| debt.card_currency.to_s.upcase }.each do |currency, debts_in_currency|
        normalized_currency = currency.to_s.upcase
        rate_reference = CurrencyConverter.reference_for_currency(normalized_currency)
        rate_symbol = TasaCambio.latest_for(rate_reference)&.symbol.to_s.strip.presence
        fallback_symbol = Account::CURRENCIES.dig(normalized_currency, :symbol) || normalized_currency
        display_symbol = rate_symbol.presence || fallback_symbol

        if normalized_currency == 'USD'
          display_total = debts_in_currency.sum { |debt| debt.card_total_balance.to_d }.round(2)
          ves_conversion = CurrencyConverter.convert(
            amount: display_total,
            from_currency: 'USD',
            to_currency: 'VES'
          )

          totals[group_totals_key(cliente, currency)] = {
            display_total: display_total,
            display_unit: 'USD',
            display_symbol: display_symbol,
            badge_label: "USD #{display_symbol}",
            ves_total: ves_conversion&.dig(:amount).to_d.round(2)
          }
          next
        end

        # Para monedas distintas de USD se muestra el saldo original y su equivalente en Bs.
        display_total = debts_in_currency.sum { |debt| debt.balance.to_d }.round(2)
        ves_conversion = CurrencyConverter.convert(
          amount: display_total,
          from_currency: normalized_currency,
          to_currency: 'VES'
        )

        badge_name = rate_reference.presence || normalized_currency

        totals[group_totals_key(cliente, currency)] = {
          display_total: display_total,
          display_unit: normalized_currency,
          display_symbol: display_symbol,
          badge_label: "#{badge_name} #{display_symbol}",
          ves_total: ves_conversion&.dig(:amount).to_d.round(2)
        }
      end
    end
  end

  def prioritize_cashea_group_first(groups)
    return groups unless current_user_admin?

    cashea_groups, other_groups = Array(groups).partition do |cliente, _debts|
      cliente&.name.to_s.strip.casecmp('cashea').zero?
    end

    sorted_others = other_groups.sort_by do |cliente, _debts|
      [cliente.present? ? 0 : 1, cliente&.name.to_s.downcase]
    end

    cashea_groups + sorted_others
  end

  def cashea_banner_url_for_admin
    return nil unless current_user_admin?

    cashea_account = current_business.accounts.where(account_type: 'cashea').order(id: :desc).first
    return nil if cashea_account.blank?
    return nil unless cashea_account.payment_method_image.attached?

    helpers.url_for(cashea_account.payment_method_image)
  rescue StandardError
    nil
  end

  def group_totals_key(cliente, currency)
    [cliente&.id || 'none', currency.to_s.upcase]
  end

  def count_debt_groups(groups)
    groups.sum do |_cliente, debts|
      debts.group_by { |debt| debt.card_currency.to_s.upcase }.size
    end
  end

  def card_currency_for_index_group(grouped_debts)
    currencies = grouped_debts.map { |debt| debt.currency.to_s.upcase }.uniq
    representative = grouped_debts.first

    if representative&.receivable? && (currencies - %w[USD VES]).empty?
      return 'USD'
    end

    return currencies.first if currencies.size == 1

    representative&.currency.to_s.upcase.presence || 'USD'
  end

  def debt_pending_for_index?(debt)
    debt.card_total_balance.to_d > 0.01.to_d
  end

  def closest_due_on(debts)
    today = Date.current

    debts
      .map(&:due_on)
      .compact
      .min_by { |due_on| [(due_on - today).to_i.abs, due_on] }
  end

  def quick_cliente_params
    params.require(:cliente).permit(:name, :phone, :address, :document_type, :document_number)
  end
end
