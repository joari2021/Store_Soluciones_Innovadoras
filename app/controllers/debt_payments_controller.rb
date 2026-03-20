class DebtPaymentsController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:deudas) }
  before_action :set_debt
  before_action :load_accounts
  before_action :load_currency_rates, only: %i[new create]

  def new
    default_account = @accounts.first
    default_currency = default_account&.currency || @debt.currency
    occurred_on = Date.current

    @debt_payment = @debt.debt_payments.new(
      account: default_account,
      occurred_at: occurred_on,
      amount: default_payment_amount(default_currency, occurred_on),
      currency: default_currency
    )

    build_payment_context(selected_currency: default_currency, occurred_on: occurred_on)
  end

  def create
    account = current_business.accounts.find_by(id: debt_payment_params[:account_id])
    payment_currency = account&.currency
    amount = parse_decimal(debt_payment_params[:amount])
    occurred_on = parse_payment_date(debt_payment_params[:occurred_at]) || Date.current
    allow_overpayment = overpayment_allowed?

    @debt_payment = @debt.debt_payments.new(
      account: account,
      amount: amount,
      currency: payment_currency,
      payment_method: debt_payment_params[:payment_method].presence,
      reference: debt_payment_params[:reference].presence,
      occurred_at: occurred_on,
      notes: debt_payment_params[:notes]
    )

    build_payment_context(selected_currency: payment_currency, occurred_on: occurred_on)

    if account.blank?
      @debt_payment.errors.add(:account, 'debe seleccionarse')
      return render :new, status: :unprocessable_entity
    end

    if payment_currency.blank?
      @debt_payment.errors.add(:account, 'debe tener una moneda configurada')
      return render :new, status: :unprocessable_entity
    end

    if @debt.receivable? && account.account_type == 'bank_account'
      duplicated_payment = find_duplicate_bank_receivable_payment(
        account_id: account.id,
        occurred_on: occurred_on,
        amount: amount
      )

      if duplicated_payment.present?
        @debt_payment.errors.add(
          :base,
          duplicate_bank_receivable_payment_message(
            account: account,
            occurred_on: occurred_on,
            amount: amount
          )
        )
        return render :new, status: :unprocessable_entity
      end
    end

    if @debt.payable? && amount.to_d.positive? && amount.to_d > account.balance.to_d
      @debt_payment.errors.add(:base, account.insufficient_balance_message(amount))
      return render :new, status: :unprocessable_entity
    end

    return render :new, status: :unprocessable_entity unless @debt_payment.valid?

    total_pending = total_balance_in_payment_currency(@grouped_debts, payment_currency, occurred_on)
    overpayment_amount = [amount.to_d - total_pending, 0.to_d].max.round(2)

    if overpayment_amount > 0.01.to_d && !allow_overpayment
      @debt_payment.errors.add(:amount, 'excede el saldo pendiente total del grupo de deudas')
      return render :new, status: :unprocessable_entity
    end

    payments_to_persist = build_grouped_payments(
      account: account,
      amount: amount,
      payment_currency: payment_currency,
      occurred_on: occurred_on,
      allow_overpayment: allow_overpayment
    )

    return render :new, status: :unprocessable_entity if payments_to_persist.blank?

    DebtPayment.transaction do
      payments_to_persist.each(&:save!)
    end

    notice = if payments_to_persist.size == 1
               'Pago registrado.'
             else
               "Pago registrado y distribuido en #{payments_to_persist.size} deudas."
             end

    if overpayment_amount > 0.01.to_d
      symbol = Account::CURRENCIES.dig(payment_currency, :symbol) || payment_currency
      overpayment_label = helpers.number_to_currency(overpayment_amount, unit: "#{symbol} ")
      notice = "#{notice} Sobregiro registrado por #{overpayment_label}."
    end

    redirect_to debt_path(@debt), notice: notice
  rescue ActiveRecord::RecordInvalid => e
    @debt_payment.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  private

  def set_debt
    current_debt = current_business.debts.find(params[:debt_id])
    @debt = group_root_for(current_debt)
    grouped_debts = debts_in_same_group(@debt)
    @grouped_debts = sort_debts([@debt] + grouped_debts.reject { |item| item.id == @debt.id })
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:currency, :name)
  end

  def load_currency_rates
    @currency_rates_to_ves = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: Date.current).to_d.to_f
    end
    @currency_rates_to_ves['VES'] = 1.0
  end

  def debt_payment_params
    params.require(:debt_payment).permit(:account_id, :amount, :payment_method, :reference, :occurred_at,
                                         :notes, :allow_overpayment)
  end

  def overpayment_allowed?
    ActiveModel::Type::Boolean.new.cast(debt_payment_params[:allow_overpayment])
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

  def find_duplicate_bank_receivable_payment(account_id:, occurred_on:, amount:)
    return nil if account_id.blank? || occurred_on.blank?

    normalized_amount = amount.to_d.round(2)
    return nil unless normalized_amount.positive?

    day_start = occurred_on.in_time_zone('America/Caracas').beginning_of_day
    day_end = occurred_on.in_time_zone('America/Caracas').end_of_day

    scope = AccountMovement
            .joins(:account)
            .where(accounts: { business_id: current_business.id })
            .where(account_id: account_id, movement_kind: 'income', amount: normalized_amount)
            .where(occurred_at: day_start..day_end)

    scope.order(created_at: :desc).first
  end

  def duplicate_bank_receivable_payment_message(account:, occurred_on:, amount:)
    normalized_amount = amount.to_d.round(2)
    date_label = occurred_on.strftime('%d/%m/%Y')

    "Ya existe un pago registrado en #{account.name} con monto #{normalized_amount.to_s('F')} #{account.currency} para la fecha #{date_label}."
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
        balance_usd_bcv: balance_usd_bcv_for_debt(debt)
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
        notes: debt_payment_params[:notes]
      )

      unless payment.valid?
        payment.errors.full_messages.each { |message| @debt_payment.errors.add(:base, message) }
        return nil
      end

      payments << payment
      remaining_amount = (remaining_amount - allocation).round(2)
    end

    if remaining_amount > 0.01.to_d
      unless allow_overpayment
        @debt_payment.errors.add(:amount, 'excede el saldo distribuible del grupo de deudas')
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
        notes: debt_payment_params[:notes]
      )

      unless overpayment.valid?
        overpayment.errors.full_messages.each { |message| @debt_payment.errors.add(:base, message) }
        return nil
      end

      payments << overpayment
      remaining_amount = 0.to_d
    end

    if payments.empty?
      @debt_payment.errors.add(:amount, 'no se pudo aplicar al grupo de deudas seleccionado')
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
      from_currency: 'USD',
      to_currency: payment_currency,
      on_date: occurred_on
    )

    conversion&.dig(:amount).to_d
  end

  def debt_amount_usd_bcv(debt)
    convert_to_usd_bcv(amount: debt.amount.to_d, currency: debt.currency, date: debt.issued_on)
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
      to_currency: 'USD',
      on_date: date
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

  def group_root_for(debt)
    root_id = debt.group_root_debt_id
    return debt if root_id.blank?

    current_business.debts.find_by(id: root_id) || debt
  end

  def debts_in_same_group(debt)
    root_id = debt.group_root_debt_id
    return [debt] if root_id.blank?

    grouped = current_business
              .debts
              .where(cliente_id: debt.cliente_id, debt_kind: debt.debt_kind)
              .includes(:debt_payments)
              .select { |candidate| candidate.group_root_debt_id == root_id }

    grouped.presence || [debt]
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
end
