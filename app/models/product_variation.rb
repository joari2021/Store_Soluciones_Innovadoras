class ProductVariation < ApplicationRecord
  belongs_to :producto
  has_many :stock_lot_variations, dependent: :nullify
  has_many :product_usages, dependent: :nullify
  has_many :venta_items, dependent: :nullify
  has_many :service_product_expenses, dependent: :nullify

  before_validation :normalize_safety_stock
  before_destroy :preserve_historical_references!

  validates :description, presence: true
  validates :safety_stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def preserve_historical_references!
    historical_name = description.to_s

    venta_items.where(variation_name: [nil, '']).update_all(variation_name: historical_name)
    product_usages.where(variation_name: [nil, '']).update_all(variation_name: historical_name)
    RecoveryInvoiceItem.where(product_variation_id: id, variation_name: [nil, ''])
                       .update_all(variation_name: historical_name)
    PackUnwrapItem.where(source_product_variation_id: id, source_variation_name: [nil, ''])
                  .update_all(source_variation_name: historical_name)
    PackUnwrapItem.where(destination_product_variation_id: id, destination_variation_name: [nil, ''])
                  .update_all(destination_variation_name: historical_name)
  end

  def normalize_safety_stock
    self[:safety_stock] = safety_stock.present? ? safety_stock.to_i : 0
  end
end
