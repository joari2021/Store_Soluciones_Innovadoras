class ExpensesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_expense, only: %i[show edit update destroy]
  before_action :load_accounts, only: %i[new create]
  before_action :load_expense_categories, only: %i[index history new create edit update]
  before_action :set_return_to_context, only: %i[new create]

  DEFAULT_EXPENSE_CATEGORIES = [
    'Nomina',
    'Alquiler',
    'Servicios basicos',
    'Impuestos y permisos',
    'Logistica y transporte',
    'Compras y suministros',
    'Mantenimiento',
    'Marketing y ventas',
    'Tecnologia y software',
    'Otros operativos'
  ].freeze

  def index
    expenses_scope = current_business.expenses.includes(:expense_payments, :expense_category)

    programmed_active_scope = expenses_scope.where.not(frequency: 'once').where.not(next_due_on: nil)

    @fixed_expenses, @fixed_finalized_expenses = split_and_sort_expenses(
      programmed_active_scope.where(expense_type: 'fixed').to_a
    )
    @variable_expenses, @variable_finalized_expenses = split_and_sort_expenses(
      programmed_active_scope.where(expense_type: 'variable').to_a
    )

    all_expenses = @fixed_expenses + @variable_expenses
    @expense_amount_usd_bcv_by_id = build_expense_amount_usd_bcv_by_id(all_expenses)
    @expenses_count = all_expenses.size
    @overdue_total = all_expenses.sum(&:overdue_count)
    @next_due_on = all_expenses.map(&:next_due_on).compact.min
  end

  def history
    @filter_from = parse_filter_date(params[:from])
    @filter_to = parse_filter_date(params[:to])
    @filter_category_id = params[:expense_category_id].to_s.presence

    expenses_scope = current_business.expenses.includes(:expense_payments, :expense_category)
    expenses_scope = apply_expense_filters(expenses_scope)

    expenses = expenses_scope.to_a
    @expense_amount_usd_bcv_by_id = build_expense_amount_usd_bcv_by_id(expenses)

    history_entries = build_unified_history_entries(expenses)
    @pagy = Pagy.new(count: history_entries.size, page: params[:page], items: 12)
    paginated_entries = history_entries[@pagy.offset, @pagy.items] || []
    @history_groups = paginated_entries.group_by do |entry|
      (entry[:occurred_at] || Time.zone.at(0)).to_date
    end

    @history_total = history_entries.size
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
        redirect_to @return_to_path, notice: 'Gasto creado exitosamente.'
      else
        render :new, status: :unprocessable_entity
      end
      return
    end

    if @expense.save
      redirect_to @return_to_path, notice: 'Gasto creado exitosamente.'
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
    destination_path = destroy_return_path

    if should_archive_expense?(@expense)
      @expense.update!(active: false, next_due_on: nil, end_date: Date.current)
      redirect_to destination_path, notice: 'Gasto archivado para conservar su historial de pagos.'
      return
    end

    Expense.transaction do
      remove_account_movements_for_expense!(@expense)
      @expense.destroy!
    end

    redirect_to destination_path, notice: 'Gasto eliminado.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to destination_path, alert: "No se pudo eliminar el gasto: #{e.message}"
  end

  private

  def set_return_to_context
    @return_to_key = params[:return_to].to_s == 'history' ? 'history' : 'index'
    @return_to_path = @return_to_key == 'history' ? history_expenses_path : expenses_path
  end

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
      :currency,
      :expense_category_id
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

    if account.account_type == 'bank_account'
      movement_method = resolved_expense_payment_method_for_movement(account, method)
      movement_attrs[:payment_method] = normalize_account_movement_method(movement_method) if movement_method.present?
    end

    movement_attrs[:reference] = reference.presence if reference.present?

    account.account_movements.create!(movement_attrs)
  end

  def resolved_expense_payment_method_for_movement(account, method)
    submitted_method = method.to_s.strip
    return submitted_method if submitted_method.present?

    return 'transfer' if account.account_type == 'bank_account' && account.currency.to_s.upcase == 'USD'

    nil
  end

  def build_movement_description(expense, _reference)
    base = "Gasto #{expense.name} [GASTO:#{expense.id}]"
    base
  end

  def should_archive_expense?(expense)
    expense.expense_payments.exists? && expense.frequency.to_s != 'once' && expense.next_due_on.present?
  end

  def destroy_return_path
    params[:return_to].to_s == 'history' ? history_expenses_path : expenses_path
  end

  def remove_account_movements_for_expense!(expense)
    expense.expense_payments.includes(:account).each do |payment|
      remove_account_movement_for_payment!(payment)
    end
  end

  def remove_account_movement_for_payment!(payment)
    account = payment.account
    return if account.blank?

    movement = account.account_movements
                      .where(movement_kind: 'expense')
                      .where('description LIKE ?', "%[PAGO_GASTO:#{payment.id}]%")
                      .order(created_at: :desc)
                      .first

    movement ||= account.account_movements
                       .where(movement_kind: 'expense', amount: payment.amount, occurred_at: payment.occurred_at)
                       .where('description LIKE ?', "%[GASTO:#{payment.expense_id}]%")
                       .order(created_at: :desc)
                       .first

    movement&.destroy!
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

  def load_expense_categories
    ensure_default_expense_categories!
    @expense_categories = current_business.expense_categories.order(:name)
  end

  def apply_expense_filters(scope)
    filtered = scope

    if @filter_category_id.present?
      filtered = filtered.where(expense_category_id: @filter_category_id.to_i)
    end

    if @filter_from.present?
      filtered = filtered.where('COALESCE(expenses.start_date, DATE(expenses.created_at)) >= ?', @filter_from)
    end

    if @filter_to.present?
      filtered = filtered.where('COALESCE(expenses.start_date, DATE(expenses.created_at)) <= ?', @filter_to)
    end

    filtered
  end

  def build_unified_history_entries(expenses)
    all_expenses = Array(expenses)
    return [] if all_expenses.empty?

    entries = []
    active_recurring_ids = []

    all_expenses.each do |expense|
      if expense.next_due_on.blank?
        paid_at = latest_payment_datetime_for_expense(expense)
        paid_at ||= expense.last_paid_on&.in_time_zone&.end_of_day
        next if paid_at.blank?

        entries << { kind: :finalized_expense, occurred_at: paid_at, expense: expense }
      elsif expense.frequency.to_s != 'once'
        active_recurring_ids << expense.id
      end
    end

    unless active_recurring_ids.empty?
      payments = ExpensePayment
                 .includes(:account, :expense)
                 .where(expense_id: active_recurring_ids)
                 .order(occurred_at: :desc, id: :desc)

      if @filter_from.present?
        from_time = @filter_from.in_time_zone.beginning_of_day
        payments = payments.where('occurred_at >= ?', from_time)
      end

      if @filter_to.present?
        to_time = @filter_to.in_time_zone.end_of_day
        payments = payments.where('occurred_at <= ?', to_time)
      end

      payments.each do |payment|
        entries << { kind: :payment, occurred_at: payment.occurred_at, payment: payment }
      end
    end

    entries.sort_by do |entry|
      timestamp = entry[:occurred_at] || Time.zone.at(0)
      [timestamp, entry[:kind] == :payment ? 1 : 0]
    end.reverse
  end

  def latest_payment_datetime_for_expense(expense)
    latest_payment = expense.expense_payments.max_by do |payment|
      [payment.occurred_at || Time.zone.at(0), payment.id.to_i]
    end

    latest_payment&.occurred_at
  end

  def parse_filter_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def ensure_default_expense_categories!
    return if current_business.expense_categories.exists?

    DEFAULT_EXPENSE_CATEGORIES.each do |name|
      current_business.expense_categories.create!(name: name)
    end
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

  def build_expense_amount_usd_bcv_by_id(expenses)
    conversion_cache = {}

    Array(expenses).each_with_object({}) do |expense, memo|
      latest_payment = expense.expense_payments.max_by do |payment|
        [payment.occurred_at || Time.zone.at(0), payment.id.to_i]
      end
      next if latest_payment.blank?
      next unless latest_payment.amount.present?
      next unless latest_payment.currency.to_s.upcase == 'VES'

      amount = latest_payment.amount.to_d
      date = latest_payment.occurred_at&.to_date || Date.current
      cache_key = [amount, date]

      converted = conversion_cache[cache_key]
      unless conversion_cache.key?(cache_key)
        converted = CurrencyConverter.convert(
          amount: amount,
          from_currency: 'VES',
          to_currency: 'USD',
          on_date: date
        )
        conversion_cache[cache_key] = converted
      end

      memo[expense.id] = converted&.dig(:amount).to_d
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

    now = Time.current.in_time_zone

    if raw.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
      date = Date.strptime(raw.tr('/', '-'), '%d-%m-%Y')
      return Time.zone.local(date.year, date.month, date.day, now.hour, now.min, now.sec)
    end

    if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      date = Date.iso8601(raw)
      return Time.zone.local(date.year, date.month, date.day, now.hour, now.min, now.sec)
    end

    Time.zone.parse(raw)
  rescue ArgumentError
    nil
  end
end
