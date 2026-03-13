class DebtPaymentsController < ApplicationController
  before_action :require_business
  before_action :set_debt
  before_action :load_accounts

  def new
    @debt_payment = @debt.debt_payments.new(
      occurred_at: Date.current,
      amount: default_payment_amount,
      currency: @debt.currency
    )
  end

  def create
    account = current_business.accounts.find_by(id: debt_payment_params[:account_id])
    payment_currency = debt_payment_params[:currency].presence || account&.currency
    amount = parse_decimal(debt_payment_params[:amount])
    occurred_on = parse_payment_date(debt_payment_params[:occurred_at]) || Date.current

    @debt_payment = @debt.debt_payments.new(
      account: account,
      amount: amount,
      currency: payment_currency,
      payment_method: debt_payment_params[:payment_method].presence,
      reference: debt_payment_params[:reference].presence,
      occurred_at: occurred_on,
      notes: debt_payment_params[:notes]
    )

    if account.blank?
      @debt_payment.errors.add(:account, 'debe seleccionarse')
      return render :new, status: :unprocessable_entity
    end

    if payment_currency.blank?
      @debt_payment.errors.add(:currency, 'debe seleccionarse')
      return render :new, status: :unprocessable_entity
    end

    if account.currency != payment_currency
      @debt_payment.errors.add(:account, 'debe coincidir con la moneda seleccionada para el pago')
      return render :new, status: :unprocessable_entity
    end

    return render :new, status: :unprocessable_entity unless @debt_payment.valid?

    if @debt_payment.amount_in_debt_currency > @debt.balance
      @debt_payment.errors.add(:amount, 'excede el saldo pendiente en la moneda base de la deuda')
      return render :new, status: :unprocessable_entity
    end

    DebtPayment.transaction do
      @debt_payment.save!
      create_account_movement(account, amount, occurred_on)
    end

    redirect_to debt_path(@debt), notice: 'Pago registrado.'
  rescue ActiveRecord::RecordInvalid => e
    @debt_payment.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  private

  def set_debt
    @debt = current_business.debts.find(params[:debt_id])
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:currency, :name)
  end

  def debt_payment_params
    params.require(:debt_payment).permit(:account_id, :currency, :amount, :payment_method, :reference, :occurred_at,
                                         :notes)
  end

  def create_account_movement(account, amount, occurred_on)
    movement_attrs = {
      movement_kind: @debt.receivable? ? 'income' : 'expense',
      amount: amount,
      description: build_movement_description,
      occurred_at: occurred_on
    }

    if account&.account_type == 'bank_account' && @debt_payment.payment_method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(@debt_payment.payment_method)
    end

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description
    action = @debt.receivable? ? 'Cobro deuda' : 'Pago deuda'
    base = "#{action} #{@debt.name}"
    return base if @debt_payment.reference.blank?

    "#{base} - Ref #{@debt_payment.reference}"
  end

  def normalize_account_movement_method(method)
    return 'mobile_payment' if method.to_s == 'mobile'

    method.to_s
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

  def default_payment_amount
    balance = @debt.balance
    return balance if balance.positive?

    @debt.amount.to_d
  end
end
