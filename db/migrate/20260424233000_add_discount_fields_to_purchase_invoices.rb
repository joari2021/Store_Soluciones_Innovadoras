class AddDiscountFieldsToPurchaseInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :facturas, :descuento_usd, :decimal, precision: 14, scale: 2, null: false, default: 0
    add_column :facturas, :descuento_bs, :decimal, precision: 14, scale: 2, null: false, default: 0
  end
end
