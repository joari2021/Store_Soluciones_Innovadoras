class Debt < ApplicationRecord
  DEBT_KINDS = {
    "receivable" => "Por cobrar",
    "payable" => "Por pagar",
  }.freeze

  belongs_to :business
  belongs_to :cliente, optional: true
  has_many :debt_payments, dependent: :destroy

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

  def receivable?
    debt_kind == "receivable"
  end

  def payable?
    debt_kind == "payable"
  end

  def counterparty_display_name
    cliente&.name.presence || "Sin cliente"
  end

  def counterparty_label
    "Cliente"
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

  def overdue?(today = Date.current)
    return false if due_on.blank?
    return false if balance <= 0

    due_on < today
  end

  def status_label(today = Date.current)
    return "Pagada" if balance <= 0
    return "Vencida" if overdue?(today)
    return "Parcial" if paid_amount.positive?

    "Pendiente"
  end

  def last_payment_at
    if debt_payments.loaded?
      debt_payments.map(&:occurred_at).compact.max
    else
      debt_payments.maximum(:occurred_at)
    end
  end

  private

  def apply_defaults
    self.debt_kind = "receivable" if debt_kind.blank?
    self.currency = "USD" if currency.blank?
    self.issued_on = Date.current if issued_on.blank?
    self.name = "Deuda #{Date.current.strftime("%d-%m-%Y")}" if name.blank?
  end

  def counterparty_presence
    return if cliente.present?

    errors.add(:base, "Selecciona un cliente.")
  end

  def due_after_issued
    return if due_on.blank? || issued_on.blank?
    return if due_on >= issued_on

    errors.add(:due_on, "debe ser posterior a la fecha de emision")
  end
end
