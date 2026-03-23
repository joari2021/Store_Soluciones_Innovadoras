class AddBasePriceSnapshotToVentaItems < ActiveRecord::Migration[7.1]
  def change
    add_column :venta_items, :unit_price_base_amount, :decimal, precision: 14, scale: 2
    add_column :venta_items, :unit_price_base_currency, :string

    add_index :venta_items, :unit_price_base_currency
  end
end
