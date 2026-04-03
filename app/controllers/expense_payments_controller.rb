class ExpensePaymentsController < ApplicationController
  before_action :require_business
  before_action :set_expense
  before_action :load_accounts

  def new
    @expense_payment = @expense.expense_payments.new(
      occurred_at: Time.current,
      amount: @expense.amount,
      currency: @expense.currency.presence || "USD",
    )
  end

  def create
    account = current_business.accounts.find_by(id: expense_payment_params[:account_id])
    amount = parse_decimal(expense_payment_params[:amount])
    occurred_at = parse_datetime(expense_payment_params[:occurred_at]) || Time.current

    @expense_payment = @expense.expense_payments.new(
      account: account,
      amount: amount,
      currency: account&.currency || "USD",
      payment_method: expense_payment_params[:payment_method].presence,
      reference: expense_payment_params[:reference].presence,
      occurred_at: occurred_at,
      notes: expense_payment_params[:notes],
    )

    if account.present? && amount.to_d.positive? && amount.to_d > account.balance.to_d
      @expense_payment.errors.add(:base, account.insufficient_balance_message(amount))
      return render :new, status: :unprocessable_entity
    end

    return render :new, status: :unprocessable_entity unless @expense_payment.valid?

    ExpensePayment.transaction do
      @expense_payment.save!
      create_account_movement(account, amount, occurred_at)
      @expense.register_payment!(occurred_at.to_date)
    end

    redirect_to expense_path(@expense), notice: "Pago registrado."
  rescue ActiveRecord::RecordInvalid => e
    @expense_payment.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  private

  def set_expense
    @expense = current_business.expenses.find(params[:expense_id])
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:name)
  end

  def expense_payment_params
    params.require(:expense_payment).permit(:account_id, :amount, :payment_method, :reference, :occurred_at, :notes)
  end

  def create_account_movement(account, amount, occurred_at)
    movement_attrs = {
      movement_kind: "expense",
      amount: amount,
      description: build_movement_description,
      occurred_at: occurred_at,
    }

    if account&.account_type == "bank_account" && @expense_payment.payment_method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(@expense_payment.payment_method)
    end

    movement_attrs[:reference] = @expense_payment.reference.presence if @expense_payment.reference.present?

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description
    base = "Gasto #{@expense.name} [GASTO:#{@expense.id}]"
    base
  end

  def normalize_account_movement_method(method)
    return "mobile_payment" if method.to_s == "mobile"

    method.to_s
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/[^\d,.-]/, "")
    if cleaned.include?(",") && cleaned.include?(".")
      cleaned = cleaned.gsub(".", "").tr(",", ".")
    elsif cleaned.include?(",")
      cleaned = cleaned.tr(",", ".")
    end

    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_datetime(value)
    return nil if value.blank?

    raw = value.to_s.strip

    return Date.strptime(raw.tr("/", "-"), "%d-%m-%Y").in_time_zone if raw.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})

    return Date.iso8601(raw).in_time_zone if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Time.zone.parse(raw)
  rescue ArgumentError
    nil
  end
end
