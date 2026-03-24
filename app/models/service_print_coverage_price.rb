class ServicePrintCoveragePrice < ApplicationRecord
  belongs_to :service

  before_validation :normalize_coverage_percent
  before_validation :normalize_price_bs

  validates :coverage_percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :price_bs, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered_by_coverage, -> { order(coverage_percent: :asc, id: :asc) }

  private

  def normalize_coverage_percent
    self.coverage_percent = parse_masked_decimal(coverage_percent_before_type_cast)
  end

  def normalize_price_bs
    self.price_bs = parse_masked_decimal(price_bs_before_type_cast)
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
