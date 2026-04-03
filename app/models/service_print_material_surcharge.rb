class ServicePrintMaterialSurcharge < ApplicationRecord
  belongs_to :service
  belongs_to :producto

  before_validation :normalize_description
  before_validation :normalize_surcharge_percent
  before_validation :normalize_required_quantity, if: :required_quantity_supported?

  validates :producto_id, presence: true
  validates :description, length: { maximum: 120 }, allow_blank: true
  validates :surcharge_percent,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }
  validates :required_quantity,
            presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 10_000 },
            if: :required_quantity_supported?
  validates :include_product_price_in_sale, inclusion: { in: [true, false] }
  validates :producto_id,
            uniqueness: { scope: :service_id, message: 'ya tiene un recargo configurado para este servicio.' },
            if: :enforce_unique_product_per_service?
  validate :validate_description_for_printing_service

  scope :ordered_by_product_name, lambda {
    joins(:producto).order('productos.descripcion ASC, service_print_material_surcharges.id ASC')
  }

  def display_label
    description.to_s.strip.presence || producto&.descripcion.to_s.strip
  end

  private

  def required_quantity_supported?
    self.class.column_names.include?('required_quantity')
  end

  def enforce_unique_product_per_service?
    service&.lamination_type_service?
  end

  def normalize_description
    normalized = description.to_s.strip.presence
    normalized = producto&.descripcion.to_s.strip.presence if normalized.blank? && service&.lamination_type_service?

    self.description = normalized
  end

  def normalize_surcharge_percent
    parsed = parse_masked_decimal(surcharge_percent_before_type_cast)
    parsed = 0.to_d if parsed.nil? && service&.lamination_type_service?

    self.surcharge_percent = parsed
  end

  def normalize_required_quantity
    return unless required_quantity_supported?

    raw_value = if respond_to?(:required_quantity_before_type_cast)
                  required_quantity_before_type_cast
                else
                  required_quantity
                end

    parsed = parse_masked_decimal(raw_value)
    parsed = 1.to_d if parsed.nil? || parsed <= 0

    self.required_quantity = parsed
  end

  def validate_description_for_printing_service
    return unless service&.printing_type_service?
    return if description.to_s.strip.present?

    errors.add(:description, 'no puede estar vacia para servicios de impresion.')
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
