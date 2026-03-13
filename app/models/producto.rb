class Producto < ApplicationRecord
  include PgSearch::Model
  belongs_to :business
  has_one_attached :foto
  has_many :supplier_products, dependent: :destroy
  has_many :suppliers, through: :supplier_products
  has_many :product_variations, dependent: :destroy
  has_many :stock_lots, dependent: :destroy
  has_many :stock_lot_variations, through: :stock_lots
  has_many :venta_items, dependent: :nullify
  has_many :ventas, through: :venta_items
  has_many :service_product_expenses, dependent: :nullify

  accepts_nested_attributes_for :product_variations, allow_destroy: true

  has_many :purchase_invoice_items, class_name: 'PurchaseInvoiceItem', foreign_key: :producto_id, dependent: :nullify

  validates :descripcion, presence: true

  before_validation :ensure_default_variation, on: :create
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

  def inventory_lots
    stock_lots.ordered_fifo
  end

  def inventory_remaining_quantity
    stock_lots.sum(:quantity_remaining)
  end

  def consume_variation_stock!(variation_id:, quantity_units:)
    requested = quantity_units.to_d
    raise ActiveRecord::RecordInvalid.new(self), 'Cantidad inválida para descuento.' if requested <= 0

    remaining_to_consume = requested

    transaction do
      stock_lots.ordered_fifo.each do |lot|
        consumed = lot.consume_variation_units!(variation_id: variation_id, quantity_units: remaining_to_consume)
        remaining_to_consume -= consumed
        break if remaining_to_consume <= 0
      end

      if remaining_to_consume > 0
        raise ActiveRecord::RecordInvalid.new(self),
              "Stock insuficiente para la variación seleccionada (faltan #{remaining_to_consume.to_f.round(4)} unidades)."
      end
    end
  end

  private

  def ensure_default_variation
    return if product_variations.any?

    product_variations.build(description: 'Unica')
  end

  def normalize_localized_monetary_fields
    self.precio_venta_usd = normalize_localized_decimal(precio_venta_usd_before_type_cast)
  end

  def normalize_localized_decimal(raw_value)
    return raw_value if raw_value.blank? || raw_value.is_a?(Numeric)

    sanitized = raw_value.to_s.strip.gsub('.', '').gsub(',', '.')
    BigDecimal(sanitized)
  rescue ArgumentError
    raw_value
  end
end
