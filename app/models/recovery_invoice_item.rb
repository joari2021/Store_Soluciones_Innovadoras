class RecoveryInvoiceItem < ApplicationRecord
  belongs_to :recovery_invoice
  belongs_to :producto
  belongs_to :product_variation, optional: true

  attribute :lot_breakdown, :json, default: []

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_usd, :total_price_usd, numericality: { greater_than_or_equal_to: 0 }
  validate :lot_breakdown_shape

  private

  def lot_breakdown_shape
    rows = Array(lot_breakdown)
    return errors.add(:lot_breakdown, "debe incluir al menos un lote") if rows.empty?

    valid = rows.all? do |row|
      source = row.respond_to?(:to_h) ? row.to_h : {}
      stock_lot_id = source["stock_lot_id"] || source[:stock_lot_id]
      quantity = source["quantity"] || source[:quantity]
      stock_lot_id.present? && quantity.present?
    end

    errors.add(:lot_breakdown, "tiene un formato invalido") unless valid
  end
end
