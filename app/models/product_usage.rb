class ProductUsage < ApplicationRecord
  belongs_to :business
  belongs_to :producto
  belongs_to :product_variation, optional: true
  belongs_to :user

  attribute :stock_lot_breakdown, :json, default: []

  validates :quantity, numericality: { greater_than: 0 }
  validates :used_on, presence: true
  validate :variation_belongs_to_producto
  validate :records_belong_to_same_business
  validate :stock_lot_breakdown_shape

  private

  def variation_belongs_to_producto
    return if product_variation.blank? || producto.blank?
    return if product_variation.producto_id == producto_id

    errors.add(:product_variation, 'no pertenece al producto seleccionado')
  end

  def records_belong_to_same_business
    return if business.blank?

    errors.add(:producto, 'no pertenece al negocio actual') if producto.present? && producto.business_id != business_id

    if product_variation.present? && product_variation.producto&.business_id != business_id
      errors.add(:product_variation, 'no pertenece al negocio actual')
    end

      return unless user.present?
      return if user.assigned_to_business?(business_id)

    errors.add(:user, 'no pertenece al negocio actual')
  end

  def stock_lot_breakdown_shape
    rows = Array(stock_lot_breakdown)
    return if rows.empty?

    valid = rows.all? do |row|
      source = row.respond_to?(:to_h) ? row.to_h : {}
      source['stock_lot_id'].present? && source['quantity'].present?
    end

    errors.add(:stock_lot_breakdown, 'tiene un formato invalido') unless valid
  end
end
