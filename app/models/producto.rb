class Producto < ApplicationRecord
  include PgSearch::Model

  belongs_to :business
  belongs_to :categoria
  belongs_to :profit_margin_preset, optional: true
  has_one_attached :foto
  has_many :supplier_products, dependent: :destroy
  has_many :suppliers, through: :supplier_products
  has_many :product_variations, dependent: :destroy
  has_many :stock_lots, dependent: :destroy
  has_many :stock_lot_variations, through: :stock_lots
  has_many :product_usages, dependent: :destroy
  has_many :venta_items, dependent: :nullify
  has_many :ventas, through: :venta_items
  has_many :service_product_expenses, dependent: :nullify
  has_many :pack_unwraps_as_pack,
           class_name: 'PackUnwrap',
           foreign_key: :pack_producto_id,
           dependent: :restrict_with_error,
           inverse_of: :pack_producto
  has_many :pack_unwraps_as_unit,
           class_name: 'PackUnwrap',
           foreign_key: :unit_producto_id,
           dependent: :restrict_with_error,
           inverse_of: :unit_producto

  enum :presentation, { unidad: 0, pack: 1 }, default: :unidad

  accepts_nested_attributes_for :product_variations, allow_destroy: true

  has_many :purchase_invoice_items, class_name: 'PurchaseInvoiceItem', foreign_key: :producto_id, dependent: :nullify

  validates :descripcion, presence: true
  validates :cant_presentation,
            numericality: { only_integer: true, greater_than: 0 }
  validates :porcentaje_ganancia,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :general_safety_stock,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :ensure_default_variation, on: :create
  before_validation :normalize_presentation_values
  before_validation :normalize_general_safety_stock
  before_validation :normalize_localized_monetary_fields
  pg_search_scope :whose_name_starts_with,
                  against: {
                    descripcion: 'A'
                  },
                  using: {
                    tsearch: { prefix: true }
                  }

  # Helper de conversion cuando haga falta mostrar valores en Bs
  def calcular_precio_bs(valor_en_dolares)
    tasa = TasaCambio.latest_value('Dolar BCV') || 0
    (valor_en_dolares * tasa).round(2)
  end

  def total_quantity
    total_from_variations = stock_lot_variations.sum(:quantity_remaining).to_d
    return total_from_variations if total_from_variations.positive?

    stock_lots.sum(:quantity_remaining).to_d
  end

  def presentation_display_suffix
    return '(unidad)' if unidad?

    "(pack de #{cant_presentation.to_i} unid)"
  end

  def display_name_with_presentation
    "#{descripcion} #{presentation_display_suffix}".squish
  end

  def inventory_lots
    stock_lots.ordered_fifo
  end

  def inventory_remaining_quantity
    stock_lots.sum(:quantity_remaining)
  end

  def highest_active_lot_unit_cost_usd
    stock_lots
      .select { |lot| lot.quantity_remaining.to_d.positive? }
      .map { |lot| lot.unit_cost_usd.to_d }
      .max
  end

  def target_margin_percentage
    preset_percentage = if self.class.reflect_on_association(:profit_margin_preset).present? && respond_to?(:profit_margin_preset)
                          profit_margin_preset&.percentage
                        end
    return preset_percentage.to_d if preset_percentage.present?

    return nil if porcentaje_ganancia.blank?

    porcentaje_ganancia.to_d
  end

  def expected_price_usd_from_target_margin(cost_usd = highest_active_lot_unit_cost_usd)
    return nil unless cost_usd.to_d.positive?

    margin = target_margin_percentage
    return nil if margin.nil?

    (cost_usd.to_d * (1 + margin / 100)).round(2)
  end

  def below_target_margin_for_highest_active_lot?
    highest_cost = highest_active_lot_unit_cost_usd
    expected_price = expected_price_usd_from_target_margin(highest_cost)
    return false if expected_price.nil?

    precio_venta_usd.to_d < expected_price
  end

  def consume_variation_stock!(variation_id:, quantity_units:)
    consume_variation_stock_internal!(variation_id: variation_id, quantity_units: quantity_units, with_breakdown: false)
    nil
  end

  def consume_variation_stock_with_breakdown!(variation_id:, quantity_units:)
    consume_variation_stock_internal!(variation_id: variation_id, quantity_units: quantity_units, with_breakdown: true)
  end

  private

  def consume_variation_stock_internal!(variation_id:, quantity_units:, with_breakdown:)
    requested = quantity_units.to_d
    raise ActiveRecord::RecordInvalid.new(self), 'Cantidad inválida para descuento.' if requested <= 0

    remaining_to_consume = requested
    breakdown = []

    transaction do
      stock_lots.ordered_fifo.each do |lot|
        consumed = lot.consume_variation_units!(variation_id: variation_id, quantity_units: remaining_to_consume)
        if with_breakdown && consumed.positive?
          breakdown << {
            stock_lot_id: lot.id,
            quantity: consumed.to_d,
            unit_cost_usd: lot.unit_cost_usd.to_d,
          }
        end
        remaining_to_consume -= consumed
        break if remaining_to_consume <= 0
      end

      if remaining_to_consume > 0
        raise ActiveRecord::RecordInvalid.new(self),
              "Stock insuficiente para la variación seleccionada (faltan #{remaining_to_consume.to_f.round(4)} unidades)."
      end
    end

    with_breakdown ? breakdown : nil
  end

  def ensure_default_variation
    return if product_variations.any?

    product_variations.build(description: 'Unica', safety_stock: 0)
  end

  def normalize_presentation_values
    self.presentation = :unidad if presentation.blank?
    self.cant_presentation = 1 if cant_presentation.blank?
    self.cant_presentation = 1 if unidad?
  end

  def normalize_general_safety_stock
    self[:general_safety_stock] = general_safety_stock.present? ? general_safety_stock.to_i : 0
  end

  def normalize_localized_monetary_fields
    self.precio_venta_usd = normalize_localized_decimal(precio_venta_usd_before_type_cast)
    porcentaje_raw = if respond_to?(:porcentaje_ganancia_before_type_cast)
                       porcentaje_ganancia_before_type_cast
                     else
                       porcentaje_ganancia
                     end
    self.porcentaje_ganancia = normalize_localized_decimal(porcentaje_raw)
  end

  def normalize_localized_decimal(raw_value)
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
    raw_value
  end
end
