class AddPackPresentationAndUnpackHistories < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :presentation, :integer, default: 0, null: false
    add_column :productos, :cant_presentation, :integer, default: 1, null: false

    change_column_null :stock_lots, :factura_item_id, true

    create_table :pack_unwraps do |t|
      t.references :business, null: false, foreign_key: true
      t.references :pack_producto, null: false, foreign_key: { to_table: :productos }
      t.references :unit_producto, null: false, foreign_key: { to_table: :productos }
      t.references :user, null: false, foreign_key: true
      t.integer :cant_presentation, null: false
      t.decimal :total_packs_opened, precision: 12, scale: 2, default: 0, null: false
      t.decimal :total_units_created, precision: 12, scale: 2, default: 0, null: false
      t.date :performed_on, null: false
      t.datetime :performed_at, null: false
      t.text :notes

      t.timestamps
    end

    create_table :pack_unwrap_items do |t|
      t.references :pack_unwrap, null: false, foreign_key: true
      t.references :source_product_variation, null: false, foreign_key: { to_table: :product_variations }
      t.references :destination_product_variation, null: false, foreign_key: { to_table: :product_variations }
      t.references :source_stock_lot, null: false, foreign_key: { to_table: :stock_lots }
      t.references :destination_stock_lot, null: false, foreign_key: { to_table: :stock_lots }
      t.decimal :packs_opened, precision: 12, scale: 2, null: false
      t.decimal :units_created, precision: 12, scale: 2, null: false
      t.decimal :source_unit_cost_usd, precision: 12, scale: 2, null: false
      t.decimal :destination_unit_cost_usd, precision: 12, scale: 2, null: false

      t.timestamps
    end

    add_index :pack_unwraps, :performed_on
    add_index :pack_unwraps, %i[business_id performed_on]
  end
end
