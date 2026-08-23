class RecoveryInvoiceItem < ApplicationRecord
  belongs_to :recovery_invoice
  belongs_to :producto
  belongs_to :product_variation, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_usd, :total_price_usd, numericality: { greater_than_or_equal_to: 0 }
end
