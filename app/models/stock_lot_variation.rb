class StockLotVariation < ApplicationRecord
  belongs_to :stock_lot
  belongs_to :product_variation, optional: true

  validates :variation_description, presence: true
  validates :quantity_in, :quantity_remaining, numericality: { greater_than_or_equal_to: 0 }
end
