class AddProductNameToFacturaItems < ActiveRecord::Migration[7.0]
  def up
    add_column :factura_items, :product_name, :string
    change_column_null :factura_items, :producto_id, true

    if foreign_key_exists?(:factura_items, :productos)
      remove_foreign_key :factura_items, :productos
    end
    add_foreign_key :factura_items, :productos, column: :producto_id, on_delete: :nullify

    execute <<~SQL.squish
      UPDATE factura_items
      SET product_name = productos.descripcion
      FROM productos
      WHERE factura_items.producto_id = productos.id
        AND factura_items.product_name IS NULL
    SQL
  end

  def down
    remove_foreign_key :factura_items, :productos if foreign_key_exists?(:factura_items, :productos)
    change_column_null :factura_items, :producto_id, false
    remove_column :factura_items, :product_name
    add_foreign_key :factura_items, :productos, column: :producto_id
  end
end
