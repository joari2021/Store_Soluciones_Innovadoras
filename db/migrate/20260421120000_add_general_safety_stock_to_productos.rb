class AddGeneralSafetyStockToProductos < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :general_safety_stock, :integer, null: false, default: 0
  end
end
