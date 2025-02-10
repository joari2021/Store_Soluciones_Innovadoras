class AddCamposToProductos < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :min_stock, :integer
    add_column :productos, :max_stock, :integer
  end
end
