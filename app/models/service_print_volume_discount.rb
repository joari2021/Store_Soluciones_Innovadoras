class ServicePrintVolumeDiscount < ApplicationRecord
  belongs_to :service

  before_validation :normalize_min_quantity
  before_validation :normalize_discount_percent

  validates :min_quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :discount_percent, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  private

  def normalize_min_quantity
    raw_value = if respond_to?(:min_quantity_before_type_cast)
                  min_quantity_before_type_cast
                else
                  min_quantity
                end

    parsed = parse_masked_decimal(raw_value)
    self.min_quantity = parsed&.to_i
  end

  def normalize_discount_percent
    self.discount_percent = parse_masked_decimal(discount_percent_before_type_cast)
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
end
