class ExpensePayment < ApplicationRecord
  PAYMENT_METHODS = {
    "transfer" => "Transferencia",
    "mobile" => "Pago movil",
  }.freeze

  belongs_to :expense
  belongs_to :account

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :occurred_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :payment_method_rules
  validate :reference_rules

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.to_s.humanize
  end

  private

  def payment_method_rules
    return if account.blank?

    if account.account_type == "bank_account" && account.currency == "VES"
      errors.add(:payment_method, "es requerido") if payment_method.blank?
    elsif payment_method.present?
      errors.add(:payment_method, "solo aplica a cuentas bancarias en Bs")
    end
  end

  def reference_rules
    return if account.blank?
    return unless account.account_type == "bank_account" && account.currency == "VES"
    return if payment_method.blank?

    if reference.blank?
      errors.add(:reference, "es requerido")
      return
    end

    errors.add(:reference, "debe tener 4 digitos") unless reference.to_s.match?(/\A\d{4}\z/)
  end
end
