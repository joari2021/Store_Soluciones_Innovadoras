module ServiceExpenseAmountSync
  extend ActiveSupport::Concern

  BOLIVAR_REFERENCE = 'Bs'.freeze
  LEGACY_USD_REFERENCE = '$'.freeze
  DEFAULT_REFERENCE = 'Dolar BCV'.freeze

  included do
    before_validation :normalize_masked_amounts
    before_validation :normalize_currency_reference
    before_validation :sync_amounts_from_reference_currency

    validates :currency_reference, presence: true
    validates :amount_reference, numericality: { greater_than_or_equal_to: 0 }

    validates :amount_usd, numericality: { greater_than_or_equal_to: 0 }
    validates :amount_bs, numericality: { greater_than_or_equal_to: 0 }

    validate :currency_reference_must_exist
  end

  def current_amount_bs
    reference_amount = amount_reference.to_d

    if reference_amount.positive?
      reference_rate = currency_reference_rate_to_bs
      return (reference_amount * reference_rate).round(2) if reference_rate.positive?
    end

    amount_bs.to_d.round(2)
  end

  def current_amount_usd(tasa_dolar: nil)
    bs_value = current_amount_bs

    if bs_value.positive?
      rate = tasa_dolar.to_d
      rate = TasaCambio.latest_value('Dolar BCV').to_d unless rate.positive?
      return (bs_value / rate).round(2) if rate.positive?
    end

    amount_usd.to_d.round(2)
  end

  private

  def normalize_masked_amounts
    self.amount_reference = parse_masked_decimal(amount_reference_before_type_cast)
    self.amount_usd = parse_masked_decimal(amount_usd_before_type_cast)
    self.amount_bs = parse_masked_decimal(amount_bs_before_type_cast)

    self.amount_reference = 0 if amount_reference.nil?
    self.amount_usd = 0 if amount_usd.nil?
    self.amount_bs = 0 if amount_bs.nil?
  end

  def normalize_currency_reference
    normalized = String(currency_reference || '').strip
    normalized = DEFAULT_REFERENCE if normalized.blank?
    normalized = DEFAULT_REFERENCE if normalized == LEGACY_USD_REFERENCE

    self.currency_reference = normalized
  end

  def parse_masked_decimal(raw_value)
    return raw_value if raw_value.is_a?(Numeric) || raw_value.is_a?(BigDecimal)

    compact = String(raw_value || '')
              .strip
              .gsub(/\s/, '')
              .gsub(/[^\d.,-]/, '')
    return nil if compact.blank?

    normalized = if compact.include?(',')
                   compact.gsub('.', '').gsub(',', '.')
                 elsif /^\d{1,3}(\.\d{3})+$/.match?(compact)
                   compact.gsub('.', '')
                 else
                   compact
                 end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end

  def sync_amounts_from_reference_currency
    rate = TasaCambio.latest_value('Dolar BCV').to_d
    reference_rate = currency_reference_rate_to_bs
    reference_amount = amount_reference.to_d

    unless rate.positive? && reference_rate.positive? && reference_amount.positive?
      self.amount_bs = 0
      self.amount_usd = 0
      return
    end

    converted_bs = (reference_amount * reference_rate).round(2)

    self.amount_bs = converted_bs
    self.amount_usd = (converted_bs / rate).round(2)
  end

  def currency_reference_must_exist
    reference = String(currency_reference || '').strip
    return if reference.blank?
    return if reference == BOLIVAR_REFERENCE
    return if TasaCambio.latest_for(reference).present?

    errors.add(:currency_reference, 'debe ser una tasa registrada o Bs')
  end

  def currency_reference_rate_to_bs
    reference = String(currency_reference || '').strip
    return 1.to_d if reference == BOLIVAR_REFERENCE

    TasaCambio.latest_value(reference).to_d
  end
end
