class StockLot < ApplicationRecord
  belongs_to :producto
  belongs_to :purchase_invoice_item, class_name: 'PurchaseInvoiceItem', foreign_key: :factura_item_id, optional: true
  belongs_to :supplier, optional: true
  has_many :stock_lot_variations, dependent: :destroy

  validates :unit_cost_usd, :quantity_in, :quantity_remaining, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered_fifo, -> { order(purchased_at: :asc, created_at: :asc) }

  def supplier_display_name
    supplier_name.presence || supplier&.nombre || 'Proveedor'
  end

  def available_variation_units(variation_id)
    row = variation_row_for(variation_id)
    return row.quantity_remaining.to_d if row

    if can_use_unique_variation_stock?(variation_id) && stock_lot_variations.empty?
      units_per_pack = purchase_invoice_item&.unid_x_pack.to_d
      multiplier = units_per_pack.positive? ? units_per_pack : 1.to_d
      return quantity_remaining.to_d * multiplier
    end

    0.to_d
  end

  def consume_variation_units!(variation_id:, quantity_units:)
    requested = quantity_units.to_d
    return 0.to_d if requested <= 0

    row = variation_row_for(variation_id, create_if_missing: true)
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

  def variation_row_for(variation_id, create_if_missing: false)
    row = stock_lot_variations.find_by(product_variation_id: variation_id)
    return row if row

    return nil unless can_use_unique_variation_stock?(variation_id)

    unique_variation = producto.product_variations.order(:id).first
    unique_name = unique_variation&.description.to_s.strip

    row = stock_lot_variations.find_by(product_variation_id: nil)
    if unique_name.present?
      row ||= stock_lot_variations.find_by('LOWER(variation_description) = ?',
                                           unique_name.downcase)
    end

    if row
      row.update!(product_variation_id: variation_id) if row.product_variation_id != variation_id
      return row
    end

    return nil unless create_if_missing

    units_per_pack = purchase_invoice_item&.unid_x_pack.to_d
    multiplier = units_per_pack.positive? ? units_per_pack : 1.to_d
    quantity_remaining_units = quantity_remaining.to_d * multiplier
    quantity_in_units = quantity_in.to_d * multiplier
    return nil unless quantity_remaining_units.positive?

    stock_lot_variations.create!(
      product_variation_id: variation_id,
      variation_description: unique_name.presence || 'Unica',
      quantity_in: quantity_in_units,
      quantity_remaining: quantity_remaining_units
    )
  end

  def can_use_unique_variation_stock?(variation_id)
    return false if variation_id.blank?

    unique_variation = producto.product_variations.order(:id).first
    unique_variation.present? && producto.product_variations.size == 1 && unique_variation.id == variation_id
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
