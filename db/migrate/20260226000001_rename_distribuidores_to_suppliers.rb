class RenameDistribuidoresToSuppliers < ActiveRecord::Migration[7.0]
  def up
    rename_table :distribuidores, :suppliers
    rename_table :distribuidor_productos, :supplier_products

    if column_exists?(:supplier_products, :distribuidor_id)
      rename_column :supplier_products, :distribuidor_id, :supplier_id
    end
    if column_exists?(:facturas, :distribuidor_id)
      rename_column :facturas, :distribuidor_id, :supplier_id
    end

    if foreign_key_exists?(:supplier_products, :distribuidores)
      remove_foreign_key :supplier_products, :distribuidores
    end
    if foreign_key_exists?(:facturas, :distribuidores)
      remove_foreign_key :facturas, :distribuidores
    end

    add_foreign_key :supplier_products, :suppliers, column: :supplier_id unless foreign_key_exists?(:supplier_products, :suppliers)
    add_foreign_key :facturas, :suppliers, column: :supplier_id unless foreign_key_exists?(:facturas, :suppliers)

    if index_exists?(:supplier_products, [:supplier_id, :producto_id], name: "index_distribuidor_producto_on_distribuidor_producto")
      rename_index :supplier_products, "index_distribuidor_producto_on_distribuidor_producto", "index_supplier_products_on_supplier_id_and_producto_id"
    end

    unless index_exists?(:supplier_products, [:supplier_id, :producto_id], name: "index_supplier_products_on_supplier_id_and_producto_id")
      add_index :supplier_products, [:supplier_id, :producto_id], name: "index_supplier_products_on_supplier_id_and_producto_id"
    end
  end

  def down
    if foreign_key_exists?(:supplier_products, :suppliers)
      remove_foreign_key :supplier_products, :suppliers
    end
    if foreign_key_exists?(:facturas, :suppliers)
      remove_foreign_key :facturas, :suppliers
    end

    if column_exists?(:supplier_products, :supplier_id)
      rename_column :supplier_products, :supplier_id, :distribuidor_id
    end
    if column_exists?(:facturas, :supplier_id)
      rename_column :facturas, :supplier_id, :distribuidor_id
    end

    rename_table :supplier_products, :distribuidor_productos
    rename_table :suppliers, :distribuidores

    add_foreign_key :distribuidor_productos, :distribuidores, column: :distribuidor_id unless foreign_key_exists?(:distribuidor_productos, :distribuidores)
    add_foreign_key :facturas, :distribuidores, column: :distribuidor_id unless foreign_key_exists?(:facturas, :distribuidores)

    if index_exists?(:distribuidor_productos, [:distribuidor_id, :producto_id], name: "index_supplier_products_on_supplier_id_and_producto_id")
      rename_index :distribuidor_productos, "index_supplier_products_on_supplier_id_and_producto_id", "index_distribuidor_producto_on_distribuidor_producto"
    end
  end
end
