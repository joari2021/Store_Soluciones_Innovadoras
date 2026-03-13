class RemoveQuantityFromProductVariationsAndVariacionNombreFromSupplierProducts < ActiveRecord::Migration[7.1]
  def change
    if column_exists?(:product_variations, :quantity)
      remove_column :product_variations, :quantity, :decimal,
                    precision: 12,
                    scale: 4,
                    default: 0.0,
                    null: false
    end

    remove_column :supplier_products, :variacion_nombre, :string if column_exists?(:supplier_products, :variacion_nombre)
  end
end