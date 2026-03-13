class CreateStockLots < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_lots do |t|
      t.references :producto, null: false, foreign_key: true
      t.references :factura_item, null: false, foreign_key: true, index: false
      t.references :supplier, foreign_key: true
      t.decimal :unit_cost_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :quantity_in, precision: 12, scale: 4, null: false, default: 0
      t.decimal :quantity_remaining, precision: 12, scale: 4, null: false, default: 0
      t.datetime :purchased_at

      t.timestamps
    end

    add_index :stock_lots, :factura_item_id, unique: true
    add_index :stock_lots, [:producto_id, :purchased_at]
  end
end
