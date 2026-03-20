class ServiceProductExpense < ApplicationRecord
  belongs_to :service_expense_structure
  belongs_to :producto
  belongs_to :product_variation, optional: true

  before_validation :assign_default_product_variation

  validates :quantity, numericality: { greater_than: 0 }
  validate :product_variation_belongs_to_product

  def total_usd
    (producto&.precio_venta_usd.to_d * quantity.to_d).round(2)
  end

  def total_bs(tasa_dolar: nil)
    rate = tasa_dolar.to_d
    rate = TasaCambio.latest_value('Dolar BCV').to_d unless rate.positive?
    return 0.to_d unless rate.positive?

    (total_usd * rate).round(2)
  end

  private

  def assign_default_product_variation
    return if producto.blank?
    return if product_variation_id.present?

    self.product_variation_id = producto.product_variations.order(:id).limit(1).pick(:id)
  end

  def product_variation_belongs_to_product
    return if product_variation.blank? || producto.blank?
    return if product_variation.producto_id == producto_id

    errors.add(:product_variation_id, 'debe pertenecer al producto seleccionado')
  end
end
