class StockLot < ApplicationRecord
  belongs_to :producto
  belongs_to :purchase_invoice_item, class_name: 'PurchaseInvoiceItem', foreign_key: :factura_item_id
  belongs_to :supplier, optional: true
  has_many :stock_lot_variations, dependent: :destroy

  validates :unit_cost_usd, :quantity_in, :quantity_remaining, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered_fifo, -> { order(purchased_at: :asc, created_at: :asc) }

  def supplier_display_name
    supplier_name.presence || supplier&.nombre || 'Proveedor'
  end

  def available_variation_units(variation_id)
    row = stock_lot_variations.find_by(product_variation_id: variation_id)
    row&.quantity_remaining.to_d || 0.to_d
  end

  def consume_variation_units!(variation_id:, quantity_units:)
    requested = quantity_units.to_d
    return 0.to_d if requested <= 0

    row = stock_lot_variations.find_by(product_variation_id: variation_id)
    return 0.to_d unless row

    consumed = 0.to_d

    transaction do
      row.lock!
      available = row.quantity_remaining.to_d
      consumed = [available, requested].min
      break if consumed <= 0

      row.quantity_remaining = available - consumed
      row.save!

      sync_quantity_remaining_from_variations!
    end

    consumed
  end

  def sync_quantity_remaining_from_variations!
    total_units_remaining = stock_lot_variations.sum(:quantity_remaining).to_d
    units_per_pack = purchase_invoice_item&.unid_x_pack.to_d

    self.quantity_remaining = if units_per_pack.positive?
                                total_units_remaining / units_per_pack
                              else
                                total_units_remaining
                              end

    save!
  end
end
