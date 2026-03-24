class SimplifyProductosFields < ActiveRecord::Migration[7.0]
  def change
    add_column :productos, :existencia, :integer, null: false, default: 0

    remove_column :productos, :precio_costo, :decimal
    remove_column :productos, :precio_venta_bs, :decimal
    remove_column :productos, :cant_unidades, :integer
    remove_column :productos, :moneda_base_precio, :string
    remove_column :productos, :available, :boolean
  end
end
