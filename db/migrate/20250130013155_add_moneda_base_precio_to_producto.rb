class AddMonedaBasePrecioToProducto < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :moneda_base_precio, :string
    add_column :productos, :precio_venta_bs, :decimal
    rename_column :productos, :precio_venta, :precio_venta_usd
  end
end
