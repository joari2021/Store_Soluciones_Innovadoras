class Expense < ApplicationRecord
  EXPENSE_TYPES = {
    'fixed' => 'Fijo',
    'variable' => 'Variable'
  }.freeze

  FREQUENCIES = {
    'once' => { label: 'Unico', interval: nil },
    'weekly' => { label: 'Semanal', interval: 1.week },
    'biweekly' => { label: 'Quincenal', interval: 2.weeks },
    'monthly' => { label: 'Mensual', interval: 1.month },
    'quarterly' => { label: 'Trimestral', interval: 3.months },
    'semiannual' => { label: 'Semestral', interval: 6.months },
    'annual' => { label: 'Anual', interval: 1.year }
  }.freeze

  belongs_to :business
  belongs_to :expense_category, optional: true
  has_many :expense_payments, dependent: :destroy

  validates :name, presence: true
  validates :expense_type, presence: true, inclusion: { in: EXPENSE_TYPES.keys }
  validates :frequency, presence: true, inclusion: { in: FREQUENCIES.keys }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, presence: true, if: -> { amount.present? }
  validates :occurrences_limit, numericality: { greater_than: 0 }, allow_nil: true
  validate :end_date_after_start

  before_validation :apply_defaults

  def self.expense_type_options
    EXPENSE_TYPES.map { |key, label| [label, key] }
  end

  def self.frequency_options
    FREQUENCIES.map { |key, data| [data[:label], key] }
  end

  def expense_type_label
    EXPENSE_TYPES[expense_type] || expense_type.to_s.humanize
  end

  def frequency_label
    FREQUENCIES.dig(frequency, :label) || frequency.to_s.humanize
  end

  def category_label
    expense_category&.name.to_s.strip.presence || 'Sin categoria'
  end

  def schedule_enabled?
    frequency != 'once'
  end

  def interval
    FREQUENCIES.dig(frequency, :interval)
  end

  def overdue_count(today = Date.current)
    return 0 if next_due_on.blank?
    return 0 if next_due_on > today
    return 1 if frequency == 'once'

    count = 0
    cursor = next_due_on
    loop do
      break if cursor > today

      count += 1
      cursor = advance_date(cursor)
      break if cursor.nil?
      break if end_date.present? && cursor > end_date
    end

    count
  end

  def status_label
    return 'Finalizado' if next_due_on.blank?
    return 'Vencido' if overdue_count.positive?

    'Al dia'
  end

  def register_payment!(paid_on)
    self.last_paid_on = paid_on
    self.payments_count = (payments_count || 0) + 1
    self.next_due_on = compute_next_due_on(paid_on)
    self.active = next_due_on.present?
    save!
  end

  def compute_next_due_on(reference_date)
    return nil if frequency == 'once'

    base = next_due_on || start_date || reference_date
    next_date = base
    loop do
      next_date = advance_date(next_date)
      break if next_date > reference_date
    end

    return nil if end_date.present? && next_date > end_date
    return nil if occurrences_limit.present? && payments_count >= occurrences_limit

    next_date
  end

  private

  def apply_defaults
    self.expense_type = 'variable' if expense_type.blank?
    self.frequency = 'once' if frequency.blank?
    self.currency = 'USD' if currency.blank?
    self.start_date = Date.current if start_date.blank?
    self.payments_count = 0 if payments_count.nil?
    return unless next_due_on.blank? && payments_count.to_i.zero?

    self.next_due_on = start_date
  end

  def advance_date(date)
    return nil if interval.blank?

    date + interval
  end

  def end_date_after_start
    return if start_date.blank? || end_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, 'debe ser posterior a la fecha de inicio')
  end
end
