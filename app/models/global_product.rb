class GlobalProduct < ApplicationRecord
  METADATA_KEYS = %w[
    category_name
    fixed_margin_percentage
    sale_price_usd
  ].freeze

  enum :presentation, { unidad: 0, pack: 1, kg: 2 }, default: :unidad
  has_one_attached :image

  has_many :global_supplier_products, dependent: :restrict_with_error
  has_many :global_suppliers, through: :global_supplier_products

  has_many :productos, dependent: :nullify

  belongs_to :source_business, class_name: "Business", optional: true

  validates :name, presence: true
  validates :presentation, presence: true
  validates :cant_presentation, numericality: { only_integer: true, greater_than: 0 }
  validate :required_metadata_on_create, on: :create
  before_validation :normalize_presentation_values

  def presentation_display_suffix
    return "(unidad)" if unidad?
    return "(1 kg)" if kg?

    "(pack de #{cant_presentation.to_i} unids)"
  end

  def display_name_with_presentation
    "#{name} #{presentation_display_suffix}".squish
  end

  def metadata_value(key)
    metadata.to_h[key.to_s]
  end

  def category_name
    metadata_value("category_name").to_s.strip.presence
  end

  def fixed_margin_percentage
    to_decimal(metadata_value("fixed_margin_percentage"))
  end

  def sale_price_usd
    to_decimal(metadata_value("sale_price_usd"))
  end

  def assign_metadata_attributes!(attrs)
    payload = (metadata || {}).to_h

    METADATA_KEYS.each do |key|
      raw = attrs[key] || attrs[key.to_sym]
      payload[key] = normalize_metadata_value(key, raw)
    end

    self.metadata = payload
  end

  private

  def normalize_presentation_values
    self.presentation = :unidad if presentation.blank?
    self.cant_presentation = 1 if cant_presentation.blank?
    self.cant_presentation = 1 if unidad? || kg?
  end

  def normalize_metadata_value(key, raw)
    return nil if raw.blank?

    return raw.to_s.strip if key == "category_name"

    decimal = to_decimal(raw)
    decimal&.to_s("F")
  end

  def to_decimal(raw)
    return nil if raw.blank?
    return raw.to_d if raw.is_a?(Numeric)

    compact = raw.to_s.strip.gsub(/\s+/, '').gsub(/[^\d,.-]/, '')
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

  def required_metadata_on_create
    errors.add(:category_name, "debe estar asignada") if category_name.blank?
    errors.add(:fixed_margin_percentage, "debe estar seleccionado") if fixed_margin_percentage.blank?
  end
end
