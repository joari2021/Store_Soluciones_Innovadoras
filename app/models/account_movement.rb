class AccountMovement < ApplicationRecord
  MOVEMENT_KINDS = {
    'income' => 'Ingreso',
    'expense' => 'Egreso',
    'adjustment' => 'Ajuste'
  }.freeze

  PAYMENT_METHODS = {
    'transfer' => 'Transferencia',
    'mobile_payment' => 'Pago movil',
    'settlement' => 'Liquidacion'
  }.freeze

  belongs_to :account
  belongs_to :account_settlement, optional: true

  validates :movement_kind, presence: true, inclusion: { in: MOVEMENT_KINDS.keys }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :payment_method_rules

  after_commit :refresh_account_balance

  def movement_kind_label
    MOVEMENT_KINDS[movement_kind] || movement_kind.to_s.humanize
  end

  def signed_amount
    movement_kind == 'expense' ? -amount.to_d : amount.to_d
  end

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.to_s.humanize
  end

  private

  def refresh_account_balance
    Account.find_by(id: account_id)&.recalculate_balance!
  end

  def payment_method_rules
    return if account.blank?

    if account.account_type == 'bank_account'
      errors.add(:payment_method, 'es requerido') if payment_method.blank?
    elsif payment_method.present?
      errors.add(:payment_method, 'solo aplica a cuentas bancarias')
    end
  end
end
