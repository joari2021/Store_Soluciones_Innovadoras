class PackUnwrapItem < ApplicationRecord
  belongs_to :pack_unwrap
  belongs_to :source_product_variation, class_name: 'ProductVariation', optional: true
  belongs_to :destination_product_variation, class_name: 'ProductVariation', optional: true
  belongs_to :source_stock_lot, class_name: 'StockLot'
  belongs_to :destination_stock_lot, class_name: 'StockLot'

  validates :packs_opened, :units_created, :source_unit_cost_usd, :destination_unit_cost_usd,
            numericality: { greater_than: 0 }
end
