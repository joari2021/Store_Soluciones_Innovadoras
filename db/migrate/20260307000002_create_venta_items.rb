class CreateVentaItems < ActiveRecord::Migration[7.1]
  def change
    create_table :venta_items do |t|
      t.references :venta, null: false, foreign_key: { to_table: :ventas }
      t.references :producto, foreign_key: true
      t.references :product_variation, foreign_key: true
      t.string :product_name
      t.string :variation_name
      t.decimal :quantity, precision: 12, scale: 4, null: false, default: 0
      t.decimal :unit_price_usd, precision: 14, scale: 4, null: false, default: 0
      t.decimal :subtotal_usd, precision: 14, scale: 4, null: false, default: 0
      t.timestamps
    end
  end
end
