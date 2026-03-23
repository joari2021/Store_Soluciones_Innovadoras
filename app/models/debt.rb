class Debt < ApplicationRecord
  GROUP_NAME_PREFIX_REGEX = /\A\[GRP:(\d+)\]\s*/.freeze
  SERVICE_COST_LINE_STATUSES = %w[pending partial paid].freeze

  attr_writer :card_total_amount, :card_total_balance, :card_currency, :card_description_summary

  DEBT_KINDS = {
    'receivable' => 'Por cobrar',
    'payable' => 'Por pagar'
  }.freeze

  belongs_to :business
  belongs_to :cliente, optional: true
  belongs_to :venta, optional: true
  belongs_to :service, optional: true
  has_many :debt_payments, dependent: :destroy

  scope :excluding_service_cost_records, lambda {
    where('description NOT LIKE ?', '%[SERVICE_COST]%')
  }

  validates :name, presence: true
  validates :debt_kind, presence: true, inclusion: { in: DEBT_KINDS.keys }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :issued_on, presence: true
  validate :counterparty_presence
  validate :due_after_issued

  before_validation :apply_defaults

  def self.debt_kind_options
    DEBT_KINDS.map { |key, label| [label, key] }
  end

  def debt_kind_label
    DEBT_KINDS[debt_kind] || debt_kind.to_s.humanize
  end

  def display_name
    value = name.to_s.sub(GROUP_NAME_PREFIX_REGEX, '').strip
    value.presence || name.to_s
  end

  def group_root_debt_id
    match = name.to_s.match(GROUP_NAME_PREFIX_REGEX)
    return nil if match.blank?

    match[1].to_i
  end

  def grouped_record?
    group_root_debt_id.present?
  end

  def receivable?
    debt_kind == 'receivable'
  end

  def payable?
    debt_kind == 'payable'
  end

  def counterparty_display_name
    cliente&.name.presence || (payable? ? display_name.presence : nil) || 'Sin cliente'
  end

  def counterparty_label
    if cliente.present?
      'Cliente'
    else
      (payable? ? 'Proveedor' : 'Cliente')
    end
  end

  def paid_amount
    if debt_payments.loaded?
      debt_payments.sum { |payment| payment.amount_in_debt_currency.to_d }
    else
      debt_payments.sum(:amount_in_debt_currency).to_d
    end
  end

  def balance
    amount.to_d - paid_amount
  end

  def card_total_amount
    return amount.to_d if @card_total_amount.nil?

    @card_total_amount.to_d
  end

  def card_total_balance
    return balance.to_d if @card_total_balance.nil?

    @card_total_balance.to_d
  end

  def card_currency
    return currency if @card_currency.blank?

    @card_currency.to_s.upcase
  end

  def card_description_summary
    return @card_description_summary.to_s.strip if @card_description_summary.present?

    description.to_s.strip.presence || 'Sin descripcion.'
  end

  def overdue?(today = Date.current)
    return false if due_on.blank?
    return false if balance <= 0

    due_on < today
  end

  def status_label(today = Date.current)
    return 'Pagada' if balance <= 0
    return 'Vencida' if overdue?(today)
    return 'Parcial' if paid_amount.positive?

    'Pendiente'
  end

  def last_payment_at
    if debt_payments.loaded?
      debt_payments.map(&:occurred_at).compact.max
    else
      debt_payments.maximum(:occurred_at)
    end
  end

  def service_cost_details_hash
    details = self[:service_cost_details]
    details.is_a?(Hash) ? details : {}
  end

  def service_cost_lines
    Array(service_cost_details_hash['lines']).map { |row| normalize_service_cost_line(row) }
  end

  def service_cost_pending_total_usd
    service_cost_lines.sum { |line| line['pending_usd'].to_d }.round(2)
  end

  def service_cost_paid_total_usd
    service_cost_lines.sum { |line| line['paid_usd'].to_d }.round(2)
  end

  def service_cost_total_usd
    service_cost_lines.sum { |line| line['amount_usd'].to_d }.round(2)
  end

  def service_cost_overall_status
    lines = service_cost_lines
    return 'pending' if lines.empty?
    return 'paid' if lines.all? { |line| line['pending_usd'].to_d <= 0.01.to_d }
    return 'partial' if lines.any? { |line| line['paid_usd'].to_d.positive? }

    'pending'
  end

  def service_cost_record?
    description.to_s.include?('[SERVICE_COST]')
  end

  private

  def normalize_service_cost_line(raw_line)
    line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}

    classification = line['classification'].to_s
    payable_line = !%w[nested_expense product_expense].include?(classification)

    amount_usd = line['amount_usd'].to_d.round(2)
    paid_usd = if payable_line
                 line['paid_usd'].to_d.round(2)
               else
                 amount_usd
               end
    paid_usd = amount_usd if paid_usd > amount_usd

    pending_usd = (amount_usd - paid_usd).round(2)
    pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

    status = if pending_usd <= 0
               'paid'
             elsif paid_usd.positive?
               'partial'
             else
               'pending'
             end

    line.merge(
      'amount_usd' => amount_usd.to_f,
      'paid_usd' => paid_usd.to_f,
      'pending_usd' => pending_usd.to_f,
      'status' => status,
      'payable_line' => payable_line
    )
  end

  def apply_defaults
    self.debt_kind = 'receivable' if debt_kind.blank?
    self.currency = 'USD' if currency.blank?
    self.issued_on = Date.current if issued_on.blank?
    self.name = "Deuda #{Date.current.strftime('%d-%m-%Y')}" if name.blank?
  end

  def counterparty_presence
    return if cliente.present?
    return if payable?

    errors.add(:base, 'Selecciona un cliente.')
  end

  def due_after_issued
    return if due_on.blank? || issued_on.blank?
    return if due_on >= issued_on

    errors.add(:due_on, 'debe ser posterior a la fecha de emision')
  end
end
