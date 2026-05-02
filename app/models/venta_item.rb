class VentaItem < ApplicationRecord
  self.table_name = 'venta_items'
  belongs_to :venta
  belongs_to :producto, optional: true
  belongs_to :product_variation, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :unit_price_base_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :set_product_snapshot
  before_validation :set_exento_snapshot
  before_validation :set_unit_price
  before_validation :normalize_unit_price
  before_validation :normalize_base_snapshot_fields
  before_validation :calculate_subtotal
  validate :variation_matches_product

  private

  def set_product_snapshot
    self.product_name = producto&.descripcion if product_name.blank?
    self.variation_name = product_variation&.description if variation_name.blank?
  end

  def set_exento_snapshot
    return unless self.class.column_names.include?('exento')
    return unless producto.present?

    self.exento = producto.respond_to?(:exento?) ? producto.exento? : false
  end

  def set_unit_price
    return if unit_price_usd.present?

    self.unit_price_usd = producto&.precio_venta_usd
  end

  def calculate_subtotal
    return if unit_price_usd.blank? || quantity.blank?

    self.subtotal_usd = round_decimal(unit_price_usd.to_d * quantity.to_d, 2)
  end


  def normalize_base_snapshot_fields
    currency = unit_price_base_currency.to_s.strip.upcase
    self.unit_price_base_currency = currency.presence

    return if unit_price_base_amount.blank?

    # Si el producto es kg, conservar 3 decimales, si no 2
    if producto&.kg?
      self.unit_price_base_amount = round_decimal(unit_price_base_amount.to_d, 3)
    else
      self.unit_price_base_amount = round_decimal(unit_price_base_amount.to_d, 2)
    end
  end

  def normalize_unit_price
    return if unit_price_usd.blank?

    self.unit_price_usd = round_decimal(unit_price_usd.to_d, 2)
  end

  def round_decimal(value, precision)
    value.to_d.round(precision)
  end

  def variation_matches_product
    return if product_variation.blank? || producto.blank?
    return if product_variation.producto_id == producto_id

    errors.add(:product_variation_id, 'no pertenece al producto')
  end
end
