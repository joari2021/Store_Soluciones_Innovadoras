class ProductVariation < ApplicationRecord
  belongs_to :producto
  has_many :stock_lot_variations, dependent: :nullify
  has_many :venta_items, dependent: :nullify
  has_many :service_product_expenses, dependent: :nullify

  before_validation :normalize_safety_stock

  validates :description, presence: true
  validates :safety_stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def normalize_safety_stock
    self[:safety_stock] = safety_stock.present? ? safety_stock.to_i : 0
  end
end
