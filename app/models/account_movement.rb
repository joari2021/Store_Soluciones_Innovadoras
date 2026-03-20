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
  validate :sufficient_balance_for_debit

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

  def sufficient_balance_for_debit
    return if account.blank?

    required_amount = additional_debit_required
    return unless required_amount.positive?

    available_balance = account.balance.to_d
    return if required_amount <= available_balance

    errors.add(:base, account.insufficient_balance_message(required_amount, available_balance: available_balance))
  end

  def additional_debit_required
    previous_signed = signed_amount_for(
      movement_kind: movement_kind_in_database,
      amount: amount_in_database
    )
    new_signed = signed_amount_for(movement_kind: movement_kind, amount: amount)

    delta = new_signed - previous_signed
    delta.negative? ? -delta : 0.to_d
  end

  def signed_amount_for(movement_kind:, amount:)
    kind = movement_kind.to_s
    numeric_amount = amount.to_d
    return -numeric_amount if kind == 'expense'

    numeric_amount
  end
end
