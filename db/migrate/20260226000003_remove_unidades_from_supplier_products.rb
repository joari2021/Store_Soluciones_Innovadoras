class RemoveUnidadesFromSupplierProducts < ActiveRecord::Migration[7.0]
  def change
    remove_column :supplier_products, :unidades, :string
  end
end
