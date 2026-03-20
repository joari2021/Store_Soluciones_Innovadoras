class ProfitMarginPreset < ApplicationRecord
  belongs_to :business
  if Producto.column_names.include?('profit_margin_preset_id')
    has_many :productos, foreign_key: :profit_margin_preset_id,
                         dependent: :nullify
  end

  validates :percentage,
            presence: true,
            numericality: { greater_than: 0, less_than: 10_000 }
  validates :percentage, uniqueness: { scope: :business_id }

  before_validation :normalize_percentage

  private

  def normalize_percentage
    self.percentage = parse_localized_decimal(percentage_before_type_cast)
  end

  def parse_localized_decimal(raw_value)
    return raw_value if raw_value.blank? || raw_value.is_a?(Numeric)

    compact = raw_value.to_s.strip.gsub(/\s+/, '').gsub(/[^\d,.-]/, '')
    return nil if compact.blank?

    normalized = if compact.include?(',')
                   compact.delete('.').tr(',', '.')
                 elsif compact.count('.') > 1 && compact.split('.').drop(1).all? { |group| group.length == 3 }
                   compact.delete('.')
                 else
                   compact
                 end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end
end
