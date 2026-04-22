class AddGlobalMappingRefsToLocalCatalog < ActiveRecord::Migration[7.1]
  def change
    add_reference :productos, :global_product, null: true, foreign_key: true
    add_reference :suppliers, :global_supplier, null: true, foreign_key: true
    add_reference :supplier_products, :global_supplier_product, null: true, foreign_key: true

    add_index :productos,
              [:business_id, :global_product_id],
              name: :index_productos_on_business_and_global_product

    add_index :suppliers,
              [:business_id, :global_supplier_id],
              name: :index_suppliers_on_business_and_global_supplier

    add_index :supplier_products,
              [:supplier_id, :global_supplier_product_id],
              name: :index_supplier_products_on_supplier_and_global_pair
  end
end
