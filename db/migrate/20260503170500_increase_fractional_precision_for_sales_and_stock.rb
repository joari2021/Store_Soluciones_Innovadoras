class IncreaseFractionalPrecisionForSalesAndStock < ActiveRecord::Migration[7.1]
  def change
    change_column :venta_items, :quantity, :decimal, precision: 12, scale: 3, null: false, default: 0

    change_column :stock_lots, :quantity_in, :decimal, precision: 12, scale: 3, null: false, default: 0
    change_column :stock_lots, :quantity_remaining, :decimal, precision: 12, scale: 3, null: false, default: 0

    change_column :stock_lot_variations, :quantity_in, :decimal, precision: 12, scale: 3, null: false, default: 0
    change_column :stock_lot_variations, :quantity_remaining, :decimal, precision: 12, scale: 3, null: false, default: 0

    change_column :factura_items, :cantidad, :decimal, precision: 14, scale: 3, null: false
    change_column :product_usages, :quantity, :decimal, precision: 14, scale: 3, null: false
  end
end
