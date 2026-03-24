class AddVatFieldsToVentas < ActiveRecord::Migration[7.1]
  def change
    add_column :ventas, :vat_mode, :string, null: false, default: 'none'
    add_column :ventas, :vat_rate, :decimal, precision: 5, scale: 4, null: false, default: 0.16
    add_column :ventas, :subtotal_usd, :decimal, precision: 14, scale: 2, null: false, default: 0
    add_column :ventas, :vat_usd, :decimal, precision: 14, scale: 2, null: false, default: 0

    add_index :ventas, :vat_mode
  end
end
