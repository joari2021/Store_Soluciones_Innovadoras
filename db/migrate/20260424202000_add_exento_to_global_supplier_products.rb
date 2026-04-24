class AddExentoToGlobalSupplierProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :global_supplier_products, :exento, :boolean, null: false, default: false
    add_index :global_supplier_products, :exento
  end
end
