class ExpensesController < ApplicationController
  before_action :require_business
  before_action :set_expense, only: %i[show edit update destroy]
  before_action :load_accounts, only: %i[new create]

  def index
    @expenses = current_business
                .expenses
                .includes(:expense_payments)
                .order(Arel.sql('CASE WHEN next_due_on IS NULL THEN 1 ELSE 0 END'), :next_due_on, :name)

    @overdue_total = @expenses.sum(&:overdue_count)
    @next_due_on = @expenses.map(&:next_due_on).compact.min
  end

  def new
    @expense = current_business.expenses.new(
      expense_type: 'variable',
      frequency: 'once',
      start_date: Date.current
    )
  end

  def create
    @expense = current_business.expenses.new(expense_params)
    normalize_schedule(@expense)

    if register_payment_now?
      success = false
      Expense.transaction do
        @expense.save!
        success = record_initial_payment(@expense)
        raise ActiveRecord::Rollback unless success
      end

      if success
        redirect_to expenses_path, notice: 'Gasto creado exitosamente.'
      else
        render :new, status: :unprocessable_entity
      end
      return
    end

    if @expense.save
      redirect_to expenses_path, notice: 'Gasto creado exitosamente.'
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @payments = @expense.expense_payments.includes(:account).order(occurred_at: :desc)
  end

  def edit
  end

  def update
    @expense.assign_attributes(expense_params)
    normalize_schedule(@expense)

    if @expense.save
      redirect_to expenses_path, notice: 'Gasto actualizado exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy
    redirect_to expenses_path, notice: 'Gasto eliminado.'
  end

  private

  def set_expense
    @expense = current_business.expenses.find(params[:id])
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:name)
  end

  def expense_params
    params.require(:expense).permit(
      :name,
      :description,
      :expense_type,
      :frequency,
      :start_date,
      :end_date,
      :occurrences_limit,
      :amount,
      :currency
    )
  end

  def register_payment_now?
    params[:register_payment].to_s == '1'
  end

  def payment_params
    params.permit(:payment_account_id, :payment_amount, :payment_method, :payment_reference, :payment_occurred_at)
  end

  def normalize_schedule(expense)
    expense.start_date = Date.current if expense.start_date.blank?
    return unless expense.next_due_on.blank? && expense.payments_count.to_i.zero?

    expense.next_due_on = expense.start_date
  end

  def record_initial_payment(expense)
    account = current_business.accounts.find_by(id: payment_params[:payment_account_id])
    amount = parse_decimal(payment_params[:payment_amount])

    if account.nil? || amount <= 0
      expense.errors.add(:base, 'Completa el pago inicial para registrarlo.')
      return false
    end

    payment_method = payment_params[:payment_method].presence
    reference = payment_params[:payment_reference].presence
    occurred_at = parse_datetime(payment_params[:payment_occurred_at]) || Time.current

    payment = expense.expense_payments.new(
      account: account,
      amount: amount,
      currency: account.currency,
      payment_method: payment_method,
      reference: reference,
      occurred_at: occurred_at
    )

    unless payment.valid?
      payment.errors.full_messages.each { |message| expense.errors.add(:base, message) }
      return false
    end

    payment.save!
    create_account_movement(account, expense, amount, payment_method, reference, occurred_at)
    expense.register_payment!(occurred_at.to_date)
    true
  rescue ActiveRecord::RecordInvalid => e
    expense.errors.add(:base, e.message)
    false
  end

  def create_account_movement(account, expense, amount, method, reference, occurred_at)
    movement_attrs = {
      movement_kind: 'expense',
      amount: amount,
      description: build_movement_description(expense, reference),
      occurred_at: occurred_at
    }

    if account.account_type == 'bank_account' && method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(method)
    end

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description(expense, reference)
    base = "Gasto #{expense.name}"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
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

  def parse_datetime(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
