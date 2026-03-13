class DebtPayment < ApplicationRecord
  PAYMENT_METHODS = {
    'transfer' => 'Transferencia',
    'mobile' => 'Pago movil'
  }.freeze

  belongs_to :debt
  belongs_to :account

  before_validation :sync_currency_from_account
  before_validation :sync_conversion_values

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :amount_in_debt_currency, presence: true, numericality: { greater_than: 0 }
  validates :exchange_rate_to_debt_currency, presence: true, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :payment_method_rules
  validate :reference_rules
  validate :currency_matches_account

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.to_s.humanize
  end

  private

  def payment_method_rules
    return if account.blank?

    if account.account_type == 'bank_account'
      errors.add(:payment_method, 'es requerido') if payment_method.blank?
    elsif payment_method.present?
      errors.add(:payment_method, 'solo aplica a cuentas bancarias')
    end
  end

  def reference_rules
    return if account.blank?
    return unless account.account_type == 'bank_account'
    return if payment_method.blank?

    if reference.blank?
      errors.add(:reference, 'es requerido')
      return
    end

    errors.add(:reference, 'debe tener 6 digitos') unless reference.to_s.match?(/\A\d{6}\z/)
  end

  def currency_matches_account
    return if account.blank?
    return if currency.blank?
    return if account.currency == currency

    errors.add(:currency, 'debe coincidir con la moneda de la cuenta')
  end

  def sync_currency_from_account
    return if account.blank?

    self.currency = account.currency
  end

  def sync_conversion_values
    return if debt.blank?
    return if currency.blank?
    return if amount.blank?

    conversion = CurrencyConverter.convert(
      amount: amount,
      from_currency: currency,
      to_currency: debt.currency
    )

    if conversion.blank?
      errors.add(:currency, "no tiene tasa de conversion disponible hacia #{debt.currency}")
      return
    end

    self.exchange_rate_to_debt_currency = conversion[:rate]
    self.amount_in_debt_currency = conversion[:amount]
  end
end
