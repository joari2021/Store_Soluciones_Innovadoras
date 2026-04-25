class DebtPaymentsController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:deudas) }
  before_action :ensure_can_register_debt_payment!, only: %i[new create]
  before_action :ensure_can_destroy_debt_payment!, only: %i[destroy]
  before_action :set_debt
  before_action :load_accounts, only: %i[new create]
  before_action :load_intercompany_mirror_accounts, only: %i[new create]
  before_action :load_currency_rates, only: %i[new create]
  before_action :set_debt_payment, only: %i[destroy]

  def new
    redirect_to debt_path(@debt, show_return_params.merge(open_payment_modal: 1))
  end

  def destroy
    shift = cash_shift_for_payment(@debt_payment)

    if shift&.closed? && !current_user_admin?
      redirect_to debt_path(@debt, show_return_params),
                  alert: 'Este pago pertenece a un turno ya cerrado. Solo el administrador puede eliminarlo.'
      return
    end

    if shift.nil? && !current_user_admin?
      redirect_to debt_path(@debt, show_return_params),
                  alert: 'No se pudo determinar un turno abierto para este pago. Solo el administrador puede eliminarlo.'
      return
    end

    payments_to_delete = [@debt_payment] + mirror_synced_payments_for(@debt_payment)
    movements_to_delete = payments_to_delete.flat_map { |payment| linked_account_movements_for_payment(payment) }
    movements_to_delete = movements_to_delete.uniq { |movement| movement.id }

    DebtPayment.transaction do
      movements_to_delete.each(&:destroy!)
      payments_to_delete.each(&:destroy!)
    end

    notice = 'Pago eliminado junto con sus movimientos en cuentas.'
    notice = "#{notice} El pago pertenecía a un turno cerrado." if shift&.closed?
    redirect_to debt_path(@debt, show_return_params), notice: notice
  rescue ActiveRecord::RecordInvalid => e
    redirect_to debt_path(@debt, show_return_params), alert: e.message
  end

  def create
    account = @accounts.find { |item| item.id == debt_payment_params[:account_id].to_i }
    payment_currency = account&.currency
    amount = parse_decimal(debt_payment_params[:amount])
    submitted_occurred_on = parse_payment_date(debt_payment_params[:occurred_at])
    occurred_on = resolved_occurred_on_for_current_user(debt_payment_params[:occurred_at])
    allow_overpayment = @debt.receivable? || overpayment_allowed?

    @debt_payment = @debt.debt_payments.new(
      account: account,
      amount: amount,
      currency: payment_currency,
      payment_method: debt_payment_params[:payment_method].presence,
      reference: debt_payment_params[:reference].presence,
      occurred_at: occurred_on,
      notes: debt_payment_params[:notes],
    )

    selected_mirror_account = selected_intercompany_mirror_account

    unless payment_date_allowed_for_current_user?(submitted_occurred_on)
      @debt_payment.errors.add(:occurred_at, 'el encargado solo puede registrar cobros/pagos con la fecha actual')
      return handle_payment_form_error
    end

    build_payment_context(selected_currency: payment_currency, occurred_on: occurred_on)

    if account.blank?
      @debt_payment.errors.add(:account, "debe seleccionarse")
      return handle_payment_form_error
    end

    if payment_currency.blank?
      @debt_payment.errors.add(:account, "debe tener una moneda configurada")
      return handle_payment_form_error
    end

    if @intercompany_group_payment_mode && selected_mirror_account.blank?
      @debt_payment.errors.add(:base, 'Debes seleccionar la cuenta destino en el negocio contraparte para registrar el espejo.')
      return handle_payment_form_error
    end

    if @intercompany_group_payment_mode && @intercompany_mirror_business.present? &&
       selected_mirror_account.present? && selected_mirror_account.business_id != @intercompany_mirror_business.id
      @debt_payment.errors.add(:base, 'La cuenta destino seleccionada no pertenece al negocio contraparte de la factura interempresa.')
      return handle_payment_form_error
    end

    if @debt.receivable? && account.account_type == "bank_account"
      duplicated_payment = find_duplicate_bank_receivable_payment(
        account_id: account.id,
        occurred_on: occurred_on,
        amount: amount,
        reference: debt_payment_params[:reference].to_s.strip,
      )

      if duplicated_payment.present?
        @debt_payment.errors.add(
          :base,
          duplicate_bank_receivable_payment_message(
            account: account,
            occurred_on: occurred_on,
            amount: amount,
            reference: debt_payment_params[:reference].to_s.strip,
          )
        )
        return handle_payment_form_error
      end
    end

    if @debt.payable? && amount.to_d.positive? && amount.to_d > account.balance.to_d
      @debt_payment.errors.add(:base, account.insufficient_balance_message(amount))
      return handle_payment_form_error
    end

    return handle_payment_form_error unless @debt_payment.valid?

    total_pending = total_balance_in_payment_currency(@grouped_debts, payment_currency, occurred_on)
    overpayment_amount = [amount.to_d - total_pending, 0.to_d].max.round(2)

    payments_to_persist = build_grouped_payments(
      account: account,
      amount: amount,
      payment_currency: payment_currency,
      occurred_on: occurred_on,
      allow_overpayment: allow_overpayment,
    )

    return handle_payment_form_error if payments_to_persist.blank?

    DebtPayment.transaction do
      apply_intercompany_mirror_account_to_debts!(payments_to_persist, selected_mirror_account)
      payments_to_persist.each(&:save!)
    end

    notice = if payments_to_persist.size == 1
        "Pago registrado."
      else
        "Pago registrado y distribuido en #{payments_to_persist.size} deudas."
      end

    if overpayment_amount > 0.01.to_d
      symbol = Account::CURRENCIES.dig(payment_currency, :symbol) || payment_currency
      overpayment_label = helpers.number_to_currency(overpayment_amount, unit: "#{symbol} ")
      notice = "#{notice} Sobregiro registrado por #{overpayment_label}."
    end

    if ActiveModel::Type::Boolean.new.cast(params[:only_active]) && active_group_debts_after_payment.empty?
      redirect_to debts_path, notice: "#{notice} El grupo quedo saldado y ahora aparece en deudas pagadas."
    else
      redirect_to debt_path(@debt, show_return_params), notice: notice
    end
  rescue ActiveRecord::RecordInvalid => e
    @debt_payment.errors.add(:base, e.message)
    handle_payment_form_error
  end

  private

  def ensure_can_register_debt_payment!
    return if current_user_admin? || current_user_manager?

    deny_access('Solo administrador o encargado pueden registrar cobros/pagos de deudas.')
  end

  def ensure_can_destroy_debt_payment!
    return if current_user_admin? || current_user_manager?

    deny_access('Solo administrador o encargado pueden eliminar pagos de deudas.')
  end

  def set_debt
    scope = current_business.debts.excluding_service_cost_records

    if current_user_customer_mode?
      customer_cliente = current_business&.clientes&.find_by(user_id: Current.user&.id)
      scope = customer_cliente.present? ? scope.where(debt_kind: 'receivable', cliente_id: customer_cliente.id) : scope.none
    end

    current_debt = scope.find(params[:debt_id])
    @debt = group_root_for(current_debt)
    @show_group_currency = params[:group_currency].to_s.upcase.presence || @debt.currency.to_s.upcase
    @show_group_token = params[:group_token].to_s.strip.presence || @debt.try(:group_token).to_s.strip.presence

    grouped_debts = if @show_group_token.present?
                      debts_with_effective_group_token(
                        debt_kind: @debt.debt_kind,
                        token: @show_group_token,
                        currency: @show_group_currency,
                        cliente_id: @debt.cliente_id,
                      )
                    elsif params[:group_currency].present?
                      debts_for_show_group(@debt)
                    else
                      debts_in_same_group(@debt)
                    end

    @grouped_debts = sort_debts(grouped_debts).uniq { |item| item.id }
  end

  def set_debt_payment
    @debt_payment = current_business
                    .debt_payments
                    .joins(:debt)
                    .where(debts: { business_id: current_business.id })
                    .find(params[:id])
  end

  def load_accounts
    intercompany_mode = @grouped_debts.present? && @grouped_debts.all? { |debt| intercompany_invoice_debt?(debt) }

    base_scope = current_business.accounts
                                 .where.not(account_type: %w[cashea biopago pos])
                                 .where.not("REPLACE(LOWER(name), ' ', '') LIKE ?", '%payall%')

    active_scope = apply_payment_currency_filter(base_scope.where(active: true))
    @accounts = active_scope.order(:currency, :name).to_a

    if @accounts.empty? && intercompany_mode
      @using_inactive_accounts_for_intercompany = true
      @accounts = apply_payment_currency_filter(base_scope).order(:currency, :name).to_a
    end
  end

  def load_intercompany_mirror_accounts
    @intercompany_group_payment_mode = @grouped_debts.present? && @grouped_debts.all? { |debt| intercompany_invoice_debt?(debt) }
    @intercompany_mirror_business = nil
    @mirror_accounts = []

    return unless @intercompany_group_payment_mode

    mirror_businesses = @grouped_debts.filter_map { |debt| debt.mirror_debt&.business }.uniq { |business| business.id }
    if mirror_businesses.size != 1
      @intercompany_group_payment_mode = false
      return
    end

    @intercompany_mirror_business = mirror_businesses.first
    base_scope = @intercompany_mirror_business.accounts
                                              .where.not(account_type: 'cashea')
                                              .where.not("REPLACE(LOWER(name), ' ', '') LIKE ?", '%payall%')

    @mirror_accounts = base_scope.where(active: true).order(:currency, :name).to_a
    if @mirror_accounts.empty?
      @using_inactive_mirror_accounts_for_intercompany = true
      @mirror_accounts = base_scope.order(:currency, :name).to_a
    end
  end

  def apply_payment_currency_filter(scope)
    if @show_group_currency == 'USDT'
      scope.where(currency: 'USDT')
    else
      scope.where(currency: %w[USD VES])
    end
  end

  def load_currency_rates
    @currency_rates_to_ves = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: Date.current).to_d.to_f
    end
    @currency_rates_to_ves["VES"] = 1.0
  end

  def debt_payment_params
    params.require(:debt_payment).permit(:account_id, :amount, :payment_method, :reference, :occurred_at,
                                         :notes, :allow_overpayment, :mirror_account_id)
  end

  def selected_intercompany_mirror_account
    mirror_account_id = debt_payment_params[:mirror_account_id].to_i
    return nil unless mirror_account_id.positive?

    @mirror_accounts.find { |account| account.id == mirror_account_id }
  end

  def intercompany_invoice_debt?(debt)
    description = debt.description.to_s
    return false unless description.include?('[IC_MIRROR]')

    description.include?('[FACTURA_COMPRA:') || description.include?('[FACTURA_COMPRA_MIRROR:')
  end

  def apply_intercompany_mirror_account_to_debts!(payments, mirror_account)
    return unless @intercompany_group_payment_mode
    return if mirror_account.blank?

    payments.map(&:debt).uniq.each do |debt|
      next unless intercompany_invoice_debt?(debt)

      debt.update!(mirror_account: mirror_account, mirror_sync_enabled: true)
      debt.mirror_debt&.update!(mirror_sync_enabled: true)
    end
  end

  def overpayment_allowed?
    ActiveModel::Type::Boolean.new.cast(debt_payment_params[:allow_overpayment])
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(",", ".")
    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_payment_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, "%d-%m-%Y")
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def resolved_occurred_on_for_current_user(raw_value)
    return parse_payment_date(raw_value) || Date.current if current_user_admin?

    Date.current
  end

  def payment_date_allowed_for_current_user?(submitted_date)
    return true if @debt.payable?
    return true if current_user_admin?
    return true if submitted_date.blank?

    submitted_date == Date.current
  end

  def find_duplicate_bank_receivable_payment(account_id:, occurred_on:, amount:, reference:)
    return nil if account_id.blank? || occurred_on.blank? || reference.blank?

    normalized_amount = amount.to_d.round(2)
    return nil unless normalized_amount.positive?

    day_start = occurred_on.in_time_zone("America/Caracas").beginning_of_day
    day_end = occurred_on.in_time_zone("America/Caracas").end_of_day

    scope = AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where(account_id: account_id, movement_kind: "income", amount: normalized_amount)
      .where(occurred_at: day_start..day_end)
      .where(
        "account_movements.reference = :reference OR account_movements.description ~ :legacy_pattern",
        reference: reference,
        legacy_pattern: "Ref #{Regexp.escape(reference)}$",
      )

    scope.order(created_at: :desc).first
  end

  def duplicate_bank_receivable_payment_message(account:, occurred_on:, amount:, reference:)
    normalized_amount = amount.to_d.round(2)
    date_label = occurred_on.strftime("%d/%m/%Y")

    "Ya existe un pago registrado en #{account.name} con monto #{normalized_amount.to_s("F")} #{account.currency}, fecha #{date_label} y referencia #{reference}."
  end

  def default_payment_amount(target_currency = @debt.currency, occurred_on = Date.current)
    total_balance_in_payment_currency(@grouped_debts, target_currency, occurred_on)
  end

  def build_payment_context(selected_currency:, occurred_on:)
    currency = selected_currency.presence || @debt.currency
    payment_date = occurred_on || Date.current

    @grouped_total_amount_usd_bcv = total_usd_amount(@grouped_debts)
    @grouped_total_paid_usd_bcv = total_usd_paid_for_debts(@grouped_debts)
    @grouped_total_balance_usd_bcv = total_usd_balance_for_debts(@grouped_debts)
    @grouped_total_balance_in_selected_currency = total_balance_in_payment_currency(@grouped_debts, currency,
                                                                                    payment_date)
    @payment_rows = @grouped_debts.map do |debt|
      {
        debt: debt,
        balance_in_debt_currency: persisted_balance_in_debt_currency(debt),
        amount_usd_bcv: debt_amount_usd_bcv(debt),
        paid_usd_bcv: paid_amount_usd_bcv_for_debt(debt),
        balance_usd_bcv: balance_usd_bcv_for_debt(debt),
      }
    end
  end

  def build_grouped_payments(account:, amount:, payment_currency:, occurred_on:, allow_overpayment: false)
    remaining_amount = amount.to_d.round(2)
    payments = []
    ordered_debts = sort_debts(@grouped_debts)

    ordered_debts.each do |debt|
      break if remaining_amount <= 0

      max_for_debt = max_payment_amount_for_debt(debt, payment_currency, occurred_on)
      next if max_for_debt <= 0

      allocation = [remaining_amount, max_for_debt].min.to_d.round(2)
      next if allocation <= 0

      payment = debt.debt_payments.new(
        account: account,
        amount: allocation,
        currency: payment_currency,
        payment_method: debt_payment_params[:payment_method].presence,
        reference: debt_payment_params[:reference].presence,
        occurred_at: occurred_on,
        notes: debt_payment_params[:notes],
      )

      unless payment.valid?
        if zero_converted_amount_error?(payment) && absorb_rounding_into_previous_payment(payments, allocation)
          remaining_amount = (remaining_amount - allocation).round(2)
          next
        end

        payment.errors.full_messages.each { |message| @debt_payment.errors.add(:base, message) }
        return nil
      end

      payments << payment
      remaining_amount = (remaining_amount - allocation).round(2)
    end

    if remaining_amount > 0.01.to_d
      if residual_rounding_amount?(amount: remaining_amount, from_currency: payment_currency, to_currency: ordered_debts.last&.currency, occurred_on: occurred_on)
        last_payment = payments.last

        if last_payment.present?
          last_payment.amount = (last_payment.amount.to_d + remaining_amount).round(2)

          unless last_payment.valid?
            last_payment.errors.full_messages.each { |message| @debt_payment.errors.add(:base, message) }
            return nil
          end

          remaining_amount = 0.to_d
        end
      end
    end

    if remaining_amount > 0.01.to_d
      unless allow_overpayment
        @debt_payment.errors.add(:amount, "excede el saldo distribuible del grupo de deudas")
        return nil
      end

      extra_payment_debt = ordered_debts.first
      overpayment = extra_payment_debt.debt_payments.new(
        account: account,
        amount: remaining_amount,
        currency: payment_currency,
        payment_method: debt_payment_params[:payment_method].presence,
        reference: debt_payment_params[:reference].presence,
        occurred_at: occurred_on,
        notes: debt_payment_params[:notes],
      )

      unless overpayment.valid?
        if zero_converted_amount_error?(overpayment) && absorb_rounding_into_previous_payment(payments, remaining_amount)
          remaining_amount = 0.to_d
          assign_grouped_movement_flags(payments, amount)
          return payments
        end

        overpayment.errors.full_messages.each { |message| @debt_payment.errors.add(:base, message) }
        return nil
      end

      payments << overpayment
      remaining_amount = 0.to_d
    end

    if payments.empty?
      @debt_payment.errors.add(:amount, "no se pudo aplicar al grupo de deudas seleccionado")
      return nil
    end

    assign_grouped_movement_flags(payments, amount)

    payments
  end

  def assign_grouped_movement_flags(payments, total_amount)
    return if payments.blank?

    total_value = total_amount.to_d.round(2)
    primary_payment = payments.first
    primary_payment.movement_amount_override = total_value if total_value.positive?

    payments.drop(1).each do |payment|
      payment.skip_account_movement = true
    end
  end

  def residual_rounding_amount?(amount:, from_currency:, to_currency:, occurred_on:)
    return false unless amount.to_d.positive?
    return false if to_currency.blank?

    conversion = CurrencyConverter.convert(
      amount: amount,
      from_currency: from_currency,
      to_currency: to_currency,
      on_date: occurred_on,
    )

    conversion.present? && conversion[:amount].to_d <= 0
  end

  def zero_converted_amount_error?(payment)
    payment.errors.attribute_names.include?(:amount_in_debt_currency) &&
      payment.errors.where(:amount_in_debt_currency).any? do |error|
        error.type == :greater_than || error.message.to_s.include?("mayor que 0")
      end
  end

  def absorb_rounding_into_previous_payment(payments, extra_amount)
    last_payment = payments.last
    return false if last_payment.blank?

    last_payment.amount = (last_payment.amount.to_d + extra_amount.to_d).round(2)
    return true if last_payment.valid?

    last_payment.amount = (last_payment.amount.to_d - extra_amount.to_d).round(2)
    false
  end

  def total_balance_in_payment_currency(debts, payment_currency, occurred_on)
    debts.sum do |debt|
      real_balance_in_payment_currency_for_debt(debt, payment_currency, occurred_on)
    end.round(2)
  end

  def max_payment_amount_for_debt(debt, payment_currency, occurred_on)
    real_balance_in_payment_currency_for_debt(debt, payment_currency, occurred_on).round(2)
  end

  def real_balance_in_payment_currency_for_debt(debt, payment_currency, occurred_on)
    real_balance_usd = balance_usd_bcv_for_debt(debt)
    return 0.to_d unless real_balance_usd.positive?

    conversion = CurrencyConverter.convert(
      amount: real_balance_usd,
      from_currency: "USD",
      to_currency: payment_currency,
      on_date: occurred_on,
    )

    conversion&.dig(:amount).to_d
  end

  def debt_amount_usd_bcv(debt)
    convert_to_usd_bcv(amount: debt.amount.to_d, currency: debt.currency, date: debt_reference_date_for_usd(debt))
  end

  def payment_amount_usd_bcv(payment)
    convert_to_usd_bcv(amount: payment.amount.to_d, currency: payment.currency, date: payment.occurred_at)
  end

  def paid_amount_usd_bcv_for_debt(debt)
    payments = persisted_debt_payments_for(debt)
    payments.sum { |payment| payment_amount_usd_bcv(payment) }.round(2)
  end

  def balance_usd_bcv_for_debt(debt)
    (debt_amount_usd_bcv(debt) - paid_amount_usd_bcv_for_debt(debt)).round(2)
  end

  def total_usd_amount(debts)
    debts.sum { |debt| debt_amount_usd_bcv(debt) }.round(2)
  end

  def total_usd_paid_for_debts(debts)
    debts.sum { |debt| paid_amount_usd_bcv_for_debt(debt) }.round(2)
  end

  def total_usd_balance_for_debts(debts)
    debts.sum { |debt| balance_usd_bcv_for_debt(debt) }.round(2)
  end

  def convert_to_usd_bcv(amount:, currency:, date:)
    conversion = CurrencyConverter.convert(
      amount: amount,
      from_currency: currency,
      to_currency: "USD",
      on_date: date,
    )

    conversion&.dig(:amount).to_d
  end

  def persisted_debt_payments_for(debt)
    payments = debt.debt_payments.loaded? ? debt.debt_payments : debt.debt_payments.to_a
    payments.select(&:persisted?)
  end

  def persisted_balance_in_debt_currency(debt)
    paid_in_debt_currency = persisted_debt_payments_for(debt).sum { |payment| payment.amount_in_debt_currency.to_d }
    (debt.amount.to_d - paid_in_debt_currency).round(2)
  end

  def debt_reference_date_for_usd(debt)
    debt.issued_on || debt.venta&.created_at&.to_date || Date.current
  end

  def group_root_for(debt)
    return debt if debt.group_token.present?

    root_id = debt.group_root_debt_id
    return debt if root_id.blank?

    current_business.debts.find_by(id: root_id) || debt
  end

  def debts_in_same_group(debt)
    if debt.group_token.present?
      grouped = debts_with_effective_group_token(
        debt_kind: debt.debt_kind,
        token: debt.group_token,
        currency: debt.currency,
        cliente_id: debt.cliente_id,
      )

      return grouped if grouped.present?
    end

    root_id = debt.group_root_debt_id
    return [debt] if root_id.blank?

    grouped = current_business
      .debts
      .where(cliente_id: debt.cliente_id, debt_kind: debt.debt_kind)
      .includes(:debt_payments)
      .select { |candidate| candidate.group_root_debt_id == root_id }

    grouped.presence || [debt]
  end

  def debts_for_show_group(debt)
      currencies = group_scope_currencies_for(currency: @show_group_currency, debt_kind: debt.debt_kind)

    scope = current_business
            .debts
            .excluding_service_cost_records
        .where(debt_kind: debt.debt_kind, currency: currencies)
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
    if ActiveModel::Type::Boolean.new.cast(params[:only_active])
      debts = debts.select { |candidate| candidate.balance > 0.01.to_d }
    end

    debts.presence || debts_in_same_group(debt)
  end

  def show_return_params
    result = {}
    result[:group_currency] = params[:group_currency] if params[:group_currency].present?
    result[:group_cliente_id] = params[:group_cliente_id] if params[:group_cliente_id].present?
    result[:only_active] = params[:only_active] if params[:only_active].present?
    result[:group_token] = params[:group_token] if params[:group_token].present?

    if result[:group_currency].blank?
      result[:group_currency] = @debt.currency.to_s.upcase
    end

    if result[:group_cliente_id].blank?
      result[:group_cliente_id] = @debt.cliente_id.present? ? @debt.cliente_id : 'none'
    end

    if result[:group_token].blank?
      fallback_token = @debt.try(:group_token).to_s.strip
      result[:group_token] = fallback_token if fallback_token.present?
    end

    result
  end

  def linked_account_movements_for_payment(payment)
    account_movements_scope_for_business(payment.debt.business_id)
      .where(account_id: payment.account_id)
      .where('description ILIKE ?', "%[DP:#{payment.id}]%")
      .to_a
  end

  def mirror_synced_payments_for(payment)
    business_ids = [payment.debt.business_id, payment.debt.mirror_debt&.business_id].compact.uniq
    return [] if business_ids.empty?

    scope = DebtPayment.joins(:debt).where(debts: { business_id: business_ids })

    referenced_id = payment.notes.to_s[/\[MIRROR_FROM_DP:(\d+)\]/, 1].to_i
    referenced_payments = referenced_id.positive? ? scope.where(id: referenced_id).to_a : []

    mirrored_from_current = scope
                            .where('debt_payments.notes ILIKE ?', "%[MIRROR_FROM_DP:#{payment.id}]%")
                            .to_a

    (referenced_payments + mirrored_from_current).uniq(&:id)
  end

  def business_account_movements_scope
    AccountMovement.joins(:account).where(accounts: { business_id: current_business.id })
  end

  def account_movements_scope_for_business(business_id)
    AccountMovement.joins(:account).where(accounts: { business_id: business_id })
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

  def modal_request?
    ActiveModel::Type::Boolean.new.cast(params[:from_debt_show_modal])
  end

  def handle_payment_form_error
    if modal_request?
      redirect_to debt_path(@debt, show_return_params.merge(open_payment_modal: 1)),
                  alert: @debt_payment.errors.full_messages.to_sentence.presence || 'No se pudo registrar el pago.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def active_group_debts_after_payment
    if @show_group_token.present?
      grouped = debts_with_effective_group_token(
        debt_kind: @debt.debt_kind,
        token: @show_group_token,
        currency: @show_group_currency,
        cliente_id: @debt.cliente_id,
      )

      return grouped.select { |candidate| candidate.balance > 0.01.to_d }
    end

    scope = current_business
            .debts
            .excluding_service_cost_records
          .where(debt_kind: @debt.debt_kind, currency: group_scope_currencies_for(currency: @show_group_currency, debt_kind: @debt.debt_kind))
            .includes(:debt_payments)

    cliente_param = params[:group_cliente_id].to_s
    if cliente_param == 'none'
      scope = scope.where(cliente_id: nil)
    elsif cliente_param.present?
      scope = scope.where(cliente_id: cliente_param.to_i)
    elsif @debt.cliente_id.present?
      scope = scope.where(cliente_id: @debt.cliente_id)
    end

    scope.select { |candidate| candidate.balance > 0.01.to_d }
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

  def debt_group_token(debt)
    token = debt.try(:group_token).to_s.strip
    return token if token.present?

    root_id = debt.group_root_debt_id
    return "legacy-#{root_id}" if root_id.present?

    "legacy-debt-#{debt.id}"
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
      debt_group_token(candidate) == effective_token
    end

    sort_debts(debts)
  end

  def group_scope_currencies_for(currency:, debt_kind:)
    normalized_currency = currency.to_s.strip.upcase
    return [normalized_currency].reject(&:blank?) if normalized_currency.blank?
    return [normalized_currency] unless debt_kind.to_s == 'receivable'
    return %w[USD VES] if normalized_currency == 'USD'

    [normalized_currency]
  end
end
