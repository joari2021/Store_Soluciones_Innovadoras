class AccountMovement < ApplicationRecord
  MOVEMENT_KINDS = {
    "income" => "Ingreso",
    "expense" => "Egreso",
    "adjustment" => "Ajuste",
  }.freeze

  PAYMENT_METHODS = {
    "transfer" => "Transferencia",
    "third_party_transfer" => "Transferencia a tercero",
    "interbank_transfer" => "Transferencia a otro banco",
    "mobile_payment" => "Pago movil",
    "debit_card" => "Tarjeta de debito",
    "settlement" => "Liquidacion",
  }.freeze

  belongs_to :account
  belongs_to :account_settlement, optional: true
  belongs_to :cambio_efectivo, optional: true

  attr_accessor :allow_negative_balance

  validates :movement_kind, presence: true, inclusion: { in: MOVEMENT_KINDS.keys }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :payment_method_rules
  validate :reference_format_rules
  validate :sufficient_balance_for_debit

  after_commit :refresh_account_balance

  def movement_kind_label
    MOVEMENT_KINDS[movement_kind] || movement_kind.to_s.humanize
  end

  def signed_amount
    movement_kind == "expense" ? -amount.to_d : amount.to_d
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

    if account.account_type == "bank_account"
      errors.add(:payment_method, "es requerido") if payment_method.blank?
    elsif payment_method.present?
      errors.add(:payment_method, "solo aplica a cuentas bancarias")
    end
  end

  def reference_format_rules
    return unless has_attribute?(:reference)
    return if reference.blank?

    errors.add(:reference, "debe tener 4 digitos") unless reference.to_s.match?(/\A\d{4}\z/)
  end

  def sufficient_balance_for_debit
    return if account.blank?
    return if ActiveModel::Type::Boolean.new.cast(allow_negative_balance)
    return if settlement_commission_allows_overdraft?

    required_amount = additional_debit_required
    return unless required_amount.positive?

    available_balance = account.balance.to_d
    return if required_amount <= available_balance

    errors.add(:base, account.insufficient_balance_message(required_amount, available_balance: available_balance))
  end

  def settlement_commission_allows_overdraft?
    return false unless movement_kind.to_s == 'expense'
    return false unless payment_method.to_s == 'settlement'

    settlement = account_settlement
    return false if settlement.blank?

    %w[biopago pos].include?(settlement.account&.account_type.to_s)
  end

  def additional_debit_required
    previous_signed = signed_amount_for(
      movement_kind: movement_kind_in_database,
      amount: amount_in_database,
    )
    new_signed = signed_amount_for(movement_kind: movement_kind, amount: amount)

    delta = new_signed - previous_signed
    delta.negative? ? -delta : 0.to_d
  end

  def signed_amount_for(movement_kind:, amount:)
    kind = movement_kind.to_s
    numeric_amount = amount.to_d
    return -numeric_amount if kind == "expense"

    numeric_amount
  end
end
