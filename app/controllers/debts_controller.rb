class DebtsController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:deudas) }
  before_action :ensure_can_create_debt!, only: %i[new create]
  before_action :ensure_can_edit_debt!, only: %i[edit update]
  before_action :ensure_can_destroy_debt!, only: %i[destroy]
  before_action :set_debt, only: %i[show edit update destroy]
  before_action :load_parties, only: %i[new create edit update]
  before_action :load_accounts, only: %i[new create edit update]
  before_action :load_currency_rates, only: %i[new create edit update]

  def index
    @search_query = params[:q].to_s.strip

    scope = current_business
            .debts
            .excluding_service_cost_records
            .includes(:cliente, :debt_payments)

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
    @has_any_debts = all_collapsed_debts.any?

    @debts = all_collapsed_debts.select { |debt| debt_pending_for_index?(debt) }
    @receivable_debts = @debts.select(&:receivable?)
    @payable_debts = @debts.select(&:payable?)
    @receivable_paid_debts = all_collapsed_debts.select(&:receivable?).reject { |debt| debt_pending_for_index?(debt) }
    @payable_paid_debts = all_collapsed_debts.select(&:payable?).reject { |debt| debt_pending_for_index?(debt) }
    @receivable_groups = build_cliente_groups(@receivable_debts)
    @payable_groups = build_cliente_groups(@payable_debts)
    @receivable_paid_groups = build_cliente_groups(@receivable_paid_debts)
    @payable_paid_groups = build_cliente_groups(@payable_paid_debts)

    @receivable_count = @receivable_debts.size
    @payable_count = @payable_debts.size
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

    if normalized_entries.empty?
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, 'Debes agregar al menos una deuda con monto, moneda y fecha de emision.')
      render :new, status: :unprocessable_entity
      return
    end

    # Buscar grupo activo (no saldado) para el cliente y moneda (excepto USDT)
    cliente_id = shared_attrs[:cliente_id]
    moneda = shared_attrs[:currency] || 'USD'
    es_usdt = moneda.to_s.upcase == 'USDT'
    scope = current_business.debts.where(debt_kind: 'receivable')
    scope = scope.where(cliente_id: cliente_id) if cliente_id.present?
    scope = scope.where(currency: moneda)
    scope = scope.excluding_service_cost_records
    scope = scope.includes(:debt_payments)

    group_root_id = nil
    unless es_usdt
      scope.group_by { |d| d.group_root_debt_id || d.id }.each do |root_id, deudas|
        saldo_total = deudas.sum { |d| d.balance }
        if saldo_total > 0.01
          group_root_id = root_id
          break
        end
      end
    end


    debts_to_create = []
    if group_root_id.present? && !es_usdt
      # Hay grupo activo, usar el mismo prefijo
      normalized_entries.each_with_index do |entry, index|
        attrs = shared_attrs.merge(debt_attributes_from_entry(entry))
        attrs[:name] = "[GRP:#{group_root_id}] #{debt_name_for_entry(index, entry[:description])}"
        debts_to_create << current_business.debts.new(attrs)
      end
    else
      # No hay grupo activo, crear el grupo con el primer registro y su propio id
      normalized_entries.each_with_index do |entry, index|
        attrs = shared_attrs.merge(debt_attributes_from_entry(entry))
        if index == 0 && !es_usdt
          # Guardar primero para obtener el id
          temp_debt = current_business.debts.new(attrs)
          temp_debt.save(validate: false) # Guardar sin validación para obtener el id
          group_id = temp_debt.id
          temp_debt.update(name: "[GRP:#{group_id}] #{debt_name_for_entry(index, entry[:description])}")
          debts_to_create << temp_debt
        else
          # Las siguientes usan el mismo prefijo
          attrs[:name] = "[GRP:#{group_id}] #{debt_name_for_entry(index, entry[:description])}"
          debts_to_create << current_business.debts.new(attrs)
        end
      end
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
      redirect_to debts_path, notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @debt = group_root_for(@debt)
    grouped_debts = debts_in_same_edit_group(@debt)
    @grouped_debts = [@debt] + sort_debts(grouped_debts.reject { |item| item.id == @debt.id })

    @payments = DebtPayment
                .where(debt_id: @grouped_debts.map(&:id))
                .includes(:account, :debt)
                .order(occurred_at: :desc, created_at: :desc)

    @show_total_amount_usd_bcv = total_usd_amount(@grouped_debts)
    @show_total_paid_usd_bcv = total_usd_paid_for_debts(@grouped_debts)
    @show_total_balance_usd_bcv = total_usd_balance_for_card(@grouped_debts)
    @show_last_payment_at = @payments.first&.occurred_at
    @show_overdue_count = @grouped_debts.count(&:overdue?)

    @show_payment_rows = @payments.map do |payment|
      {
        payment: payment,
        equivalent_usd_bcv: payment_amount_usd_bcv(payment),
        debt_label: payment.excess_payment? ? 'Excedente' : (payment.debt&.description.to_s.strip.presence || 'Deuda sin descripcion')
      }
    end

    @show_debt_rows = @grouped_debts.map do |debt|
      {
        debt: debt,
        amount_usd_bcv: amount_in_usd_bcv_for_debt(debt.amount.to_d, debt),
        paid_usd_bcv: paid_amount_usd_bcv_for_debt(debt),
        balance_usd_bcv: real_balance_usd_bcv_for_debt(debt)
      }
    end
  end

  def edit
    @debt = group_root_for(@debt)
    grouped_debts = editable_active_debts_for(@debt)
    @debt_entries_form = grouped_debts.map { |debt| debt_entry_from_record(debt) }
  end

  def update
    @debt = group_root_for(@debt)
    @debt_entries_form = debt_entries_form_params
    normalized_entries = normalized_debt_entries
    shared_attrs = shared_debt_params

    if normalized_entries.empty?
      @debt.errors.add(:base, 'Debes agregar al menos una deuda con monto, moneda y fecha de emision.')
      render :edit, status: :unprocessable_entity
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
      render :edit, status: :unprocessable_entity
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
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @debt = group_root_for(@debt)
    grouped_debts = debts_in_same_edit_group(@debt)
    remove_movements = params[:delete_mode].to_s == 'with_movements'
    movements_to_remove = remove_movements ? linked_account_movements_for_debts(grouped_debts) : []

    Debt.transaction do
      movements_to_remove.each(&:destroy!)
      grouped_debts.each(&:destroy!)
    end

    notice = grouped_debts.size > 1 ? "#{grouped_debts.size} deudas eliminadas." : 'Deuda eliminada.'
    notice = if remove_movements
               "#{notice} #{movements_to_remove.size} movimientos de cuenta eliminados."
             else
               "#{notice} Los movimientos en cuentas se conservaron."
             end

    redirect_to debts_path, notice: notice
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
    @accounts = current_business.accounts.where(active: true).order(:name)
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
        loan_account_id: loan_account_id
      }
    end.compact

    return [default_debt_entry] if rows.empty?

    rows
  end

  def normalized_debt_entries
    debt_entries_form_params.map do |row|
      {
        amount: parse_decimal(row[:amount]),
        currency: row[:currency].to_s.strip.upcase,
        issued_on: parse_debt_date(row[:issued_on]),
        due_on: parse_debt_date(row[:due_on]),
        description: row[:description].to_s.strip.presence,
        debt_id: row[:debt_id].to_i,
        venta_id: row[:venta_id].to_i,
        loan_enabled: ActiveModel::Type::Boolean.new.cast(row[:loan_enabled]),
        loan_account_id: row[:loan_account_id].presence
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
      issued_on: Date.current.strftime('%d-%m-%Y'),
      due_on: '',
      description: '',
      loan_enabled: false,
      loan_account_id: ''
    }
  end

  def debt_entry_from_record(debt)
    loan_movement = latest_loan_account_movement_for_debt(debt)

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
    valid = true

    entries.each_with_index do |entry, index|
      next unless entry[:loan_enabled]

      account = current_business.accounts.where(active: true).find_by(id: entry[:loan_account_id])

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

      entry[:loan_amount] = conversion[:amount].to_d
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
    "Prestamo deuda: #{debt_description} - Cliente: #{cliente_name} [DEBT:#{debt.id}]"
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
      on_date: debt.issued_on
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

  def debt_sort_key(debt)
    due_on = debt.due_on
    normalized_name = debt.display_name.to_s.strip.downcase
    normalized_cliente = debt.counterparty_display_name.to_s.strip.downcase

    if due_on.present?
      [0, due_on, normalized_name, normalized_cliente, debt.id.to_i]
    else
      [1, normalized_name, normalized_cliente, debt.id.to_i]
    end
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
    root_id = debt.group_root_debt_id
    return debt if root_id.blank?

    current_business.debts.find_by(id: root_id) || debt
  end

  def debts_in_same_edit_group(debt)
    root_id = debt.group_root_debt_id
    return [debt] if root_id.blank?

    grouped = current_business
              .debts
              .where(cliente_id: debt.cliente_id, debt_kind: debt.debt_kind)
              .includes(:debt_payments)
              .select { |candidate| candidate.group_root_debt_id == root_id }

    grouped.presence || [debt]
  end

  def collapsed_group_key(debt)
    if debt.grouped_record? && debt.group_root_debt_id.present?
      "group-#{debt.group_root_debt_id}"
    else
      "single-#{debt.id}"
    end
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
                  representative.card_currency = 'USD'
                  representative.card_description_summary = card_description_summary_for(grouped_debts)
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

  def format_missing_description_count(count)
    count.to_i == 1 ? '1 deuda sin descripcion' : "#{count.to_i} deudas sin descripcion"
  end

  def build_cliente_groups(debts)
    debts
      .group_by(&:cliente)
      .map { |cliente, debts| [cliente, sort_debts(debts)] }
      .sort_by do |cliente, debts|
        first_debt = debts.first
        first_key = first_debt ? debt_sort_key(first_debt) : [1, '', '', 0]
        [first_key[0], first_key[1], cliente&.name.to_s.downcase]
      end
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
