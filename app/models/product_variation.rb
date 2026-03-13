class ProductVariation < ApplicationRecord
  belongs_to :producto
  has_many :stock_lot_variations, dependent: :nullify
  has_many :venta_items, dependent: :nullify

  validates :description, presence: true
  validates :safety_stock, numericality: { greater_than_or_equal_to: 0 }
end
