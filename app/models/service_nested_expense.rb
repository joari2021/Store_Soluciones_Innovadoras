class ServiceNestedExpense < ApplicationRecord
  BOLIVAR_REFERENCE = 'Bs'.freeze
  DEFAULT_REFERENCE = 'Bs'.freeze

  belongs_to :service_expense_structure
  belongs_to :nested_service, class_name: 'Service'

  has_one :service, through: :service_expense_structure

  before_validation :normalize_reference_fields
  before_validation :normalize_quantity_for_to_agree

  validates :quantity, numericality: { greater_than: 0 }, unless: :to_agree_nested_service?
  validates :currency_reference, presence: true
  validates :amount_reference, numericality: { greater_than_or_equal_to: 0 }

  validate :nested_service_cannot_match_parent
  validate :nested_service_must_be_available_for_nesting
  validate :currency_reference_must_exist

  def total_usd(tasa_dolar: nil, unidad_vi: nil)
    return total_usd_from_reference(tasa_dolar: tasa_dolar) if to_agree_nested_service?

    unit_price = nested_service&.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d
    (unit_price * quantity.to_d).round(2)
  end

  def total_bs(tasa_dolar: nil, unidad_vi: nil)
    return total_bs_from_reference if to_agree_nested_service?

    unit_price = nested_service&.unit_price_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d
    (unit_price * quantity.to_d).round(2)
  end

  private

  def to_agree_nested_service?
    nested_service&.to_agree?
  end

  def normalize_reference_fields
    self.amount_reference = parse_masked_decimal(amount_reference_before_type_cast)
    self.amount_reference = 0 if amount_reference.nil? || amount_reference.negative?

    normalized = String(currency_reference || '').strip
    normalized = DEFAULT_REFERENCE if normalized.blank?

    self.currency_reference = normalized
  end

  def normalize_quantity_for_to_agree
    return unless to_agree_nested_service?

    self.quantity = 1 if quantity.to_d <= 0
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

  def total_bs_from_reference
    reference_amount = amount_reference.to_d
    reference_rate = currency_reference_rate_to_bs

    return 0.to_d unless reference_amount.positive? && reference_rate.positive?

    (reference_amount * reference_rate).round(2)
  end

  def total_usd_from_reference(tasa_dolar: nil)
    bs_value = total_bs_from_reference
    return 0.to_d unless bs_value.positive?

    rate = tasa_dolar.to_d
    rate = TasaCambio.latest_value('Dolar BCV').to_d unless rate.positive?
    return 0.to_d unless rate.positive?

    (bs_value / rate).round(2)
  end

  def nested_service_cannot_match_parent
    return if nested_service_id.blank?
    return if service.blank?
    return if nested_service_id != service.id

    errors.add(:nested_service_id, 'cannot be the same as the current service')
  end

  def nested_service_must_be_available_for_nesting
    return if nested_service.blank?
    return if nested_service.nested_available?

    errors.add(:nested_service_id, 'is not enabled as nested service')
  end
end
