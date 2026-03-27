class AddAllowUnpackToProductos < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :allow_unpack, :boolean, default: false, null: false
    add_index :productos, :allow_unpack
  end
end
