class CreateStockLotVariations < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_lot_variations do |t|
      t.references :stock_lot, null: false, foreign_key: true
      t.references :product_variation, null: true, foreign_key: true
      t.string :variation_description, null: false
      t.decimal :quantity_in, precision: 12, scale: 4, null: false, default: 0
      t.decimal :quantity_remaining, precision: 12, scale: 4, null: false, default: 0

      t.timestamps
    end

    add_index :stock_lot_variations, [:stock_lot_id, :product_variation_id], name: 'index_stock_lot_variations_on_lot_and_variation'
  end
end
