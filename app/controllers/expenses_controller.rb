class ExpensesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_expense, only: %i[show edit update destroy]
  before_action :load_accounts, only: %i[new create]

  def index
    expenses_scope = current_business.expenses.includes(:expense_payments)

    @fixed_expenses, @fixed_finalized_expenses = split_and_sort_expenses(
      expenses_scope.where(expense_type: 'fixed').to_a
    )
    @variable_expenses, @variable_finalized_expenses = split_and_sort_expenses(
      expenses_scope.where(expense_type: 'variable').to_a
    )

    all_expenses = @fixed_expenses + @fixed_finalized_expenses + @variable_expenses + @variable_finalized_expenses
    @expenses_count = all_expenses.size
    @overdue_total = all_expenses.sum(&:overdue_count)
    @next_due_on = all_expenses.map(&:next_due_on).compact.min
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
    @payment_equivalents = build_payment_equivalents(@payments, @expense.currency)
  end

  def edit
  end

  def update
    @expense.assign_attributes(expense_params)
    normalize_schedule(@expense)
    recalculate_schedule_if_needed(@expense)

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
    permitted = params.require(:expense).permit(
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
    # Procesar amount para convertirlo a número si viene con máscara
    permitted[:amount] = parse_decimal(permitted[:amount]) if permitted[:amount].present?
    permitted
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

  def recalculate_schedule_if_needed(expense)
    return if expense.payments_count.to_i.zero?

    schedule_changed =
      expense.will_save_change_to_frequency? ||
      expense.will_save_change_to_start_date? ||
      expense.will_save_change_to_end_date? ||
      expense.will_save_change_to_occurrences_limit? ||
      (expense.frequency != 'once' && expense.next_due_on.blank?)

    return unless schedule_changed

    if expense.frequency == 'once'
      expense.next_due_on = nil
      expense.active = false
      return
    end

    reference_date = expense.last_paid_on || expense.start_date || Date.current

    # Forzar recalculo desde la configuracion actual y el ultimo pago.
    expense.next_due_on = nil
    expense.next_due_on = expense.compute_next_due_on(reference_date)
    expense.active = expense.next_due_on.present?
  end

  def record_initial_payment(expense)
    account = current_business.accounts.find_by(id: payment_params[:payment_account_id])
    amount = parse_decimal(payment_params[:payment_amount])

    if account.nil? || amount <= 0
      expense.errors.add(:base, 'Completa el pago inicial para registrarlo.')
      return false
    end

    if amount.to_d > account.balance.to_d
      expense.errors.add(:base, account.insufficient_balance_message(amount))
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

    movement_attrs[:reference] = reference.presence if reference.present?

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description(expense, _reference)
    base = "Gasto #{expense.name} [GASTO:#{expense.id}]"
    base
  end

  def normalize_account_movement_method(method)
    return 'mobile_payment' if method.to_s == 'mobile'

    method.to_s
  end

  def split_and_sort_expenses(expenses)
    active, finalized = expenses.partition { |expense| expense.next_due_on.present? }

    sorted_active = active.sort_by { |expense| [expense.next_due_on, expense.name.to_s.downcase] }
    sorted_finalized = finalized.sort_by { |expense| expense.name.to_s.downcase }

    [sorted_active, sorted_finalized]
  end

  def build_payment_equivalents(payments, target_currency)
    target = target_currency.to_s.upcase
    conversion_cache = {}

    payments.each_with_object({}) do |payment, memo|
      amount = payment.amount.to_d
      from = payment.currency.to_s.upcase
      date = payment.occurred_at&.to_date

      cache_key = [amount, from, target, date]
      converted = conversion_cache[cache_key]
      unless conversion_cache.key?(cache_key)
        converted = CurrencyConverter.convert(
          amount: amount,
          from_currency: from,
          to_currency: target,
          on_date: date
        )
        conversion_cache[cache_key] = converted
      end

      memo[payment.id] = converted&.dig(:amount)
    end
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/[^\d,.-]/, '')
    if cleaned.include?(',') && cleaned.include?('.')
      cleaned = cleaned.gsub('.', '').tr(',', '.')
    elsif cleaned.include?(',')
      cleaned = cleaned.tr(',', '.')
    end

    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_datetime(value)
    return nil if value.blank?

    raw = value.to_s.strip

    return Date.strptime(raw.tr('/', '-'), '%d-%m-%Y').in_time_zone if raw.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})

    return Date.iso8601(raw).in_time_zone if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Time.zone.parse(raw)
  rescue ArgumentError
    nil
  end
end
