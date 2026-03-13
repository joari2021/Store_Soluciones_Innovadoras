class Debt < ApplicationRecord
  DEBT_KINDS = {
    'receivable' => 'Por cobrar',
    'payable' => 'Por pagar'
  }.freeze

  ORIGIN_KINDS = {
    'general' => 'General',
    'loan' => 'Dinero prestado',
    'service_credit' => 'Servicio a credito',
    'sale_credit' => 'Venta a credito',
    'other' => 'Otro'
  }.freeze

  belongs_to :business
  belongs_to :cliente, optional: true
  belongs_to :supplier, optional: true
  belongs_to :loan_account, class_name: 'Account', optional: true
  has_many :debt_payments, dependent: :destroy

  validates :name, presence: true
  validates :debt_kind, presence: true, inclusion: { in: DEBT_KINDS.keys }
  validates :origin_kind, presence: true, inclusion: { in: ORIGIN_KINDS.keys }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validate :counterparty_presence
  validate :due_after_issued
  validate :loan_configuration

  before_validation :apply_defaults
  before_validation :normalize_counterparty
  before_validation :normalize_loan_settings

  def self.debt_kind_options
    DEBT_KINDS.map { |key, label| [label, key] }
  end

  def self.origin_kind_options
    ORIGIN_KINDS.map { |key, label| [label, key] }
  end

  def debt_kind_label
    DEBT_KINDS[debt_kind] || debt_kind.to_s.humanize
  end

  def origin_kind_label
    ORIGIN_KINDS[origin_kind] || origin_kind.to_s.humanize
  end

  def receivable?
    debt_kind == 'receivable'
  end

  def payable?
    debt_kind == 'payable'
  end

  def loan?
    origin_kind == 'loan'
  end

  def counterparty_display_name
    return cliente.name if cliente.present?
    return supplier.nombre if supplier.present?

    'Sin contraparte'
  end

  def counterparty_label
    return 'Cliente' if cliente.present?
    return 'Proveedor' if supplier.present?

    'Contraparte'
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

  private

  def apply_defaults
    self.debt_kind = 'receivable' if debt_kind.blank?
    self.origin_kind = 'general' if origin_kind.blank?
    self.currency = 'USD' if currency.blank?
    self.issued_on = Date.current if issued_on.blank?
  end

  def normalize_counterparty
    if receivable?
      self.supplier_id = nil
    else
      self.cliente_id = nil
    end
  end

  def normalize_loan_settings
    self.loan_account_id = nil unless loan?
  end

  def counterparty_presence
    if receivable?
      return if cliente.present?

      errors.add(:base, 'Selecciona un cliente.')
    else
      return if supplier.present?

      errors.add(:base, 'Selecciona un proveedor.')
    end
  end

  def due_after_issued
    return if due_on.blank? || issued_on.blank?
    return if due_on >= issued_on

    errors.add(:due_on, 'debe ser posterior a la fecha de emision')
  end

  def loan_configuration
    return unless loan?

    unless receivable?
      errors.add(:origin_kind, 'solo aplica para deudas por cobrar')
      return
    end

    if loan_account.blank?
      errors.add(:loan_account, 'debe seleccionarse para prestamos')
      return
    end

    if business_id.present? && loan_account.business_id != business_id
      errors.add(:loan_account, 'debe pertenecer al mismo negocio')
    end

    return if currency.blank? || loan_account.currency == currency

    errors.add(:loan_account, 'debe tener la misma moneda base de la deuda')
  end
end
