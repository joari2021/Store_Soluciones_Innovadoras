class PreserveSupplierHistoryWhenDeletingSupplier < ActiveRecord::Migration[7.1]
  def up
    add_column :facturas, :supplier_name, :string
    add_column :stock_lots, :supplier_name, :string

    execute <<~SQL
      UPDATE facturas
      SET supplier_name = suppliers.nombre
      FROM suppliers
      WHERE facturas.supplier_id = suppliers.id
        AND facturas.supplier_name IS NULL;
    SQL

    execute <<~SQL
      UPDATE stock_lots
      SET supplier_name = suppliers.nombre
      FROM suppliers
      WHERE stock_lots.supplier_id = suppliers.id
        AND stock_lots.supplier_name IS NULL;
    SQL

    remove_foreign_key :facturas, :suppliers
    change_column_null :facturas, :supplier_id, true
    add_foreign_key :facturas, :suppliers, on_delete: :nullify

    remove_foreign_key :stock_lots, :suppliers
    add_foreign_key :stock_lots, :suppliers, on_delete: :nullify
  end

  def down
    remove_foreign_key :stock_lots, :suppliers
    add_foreign_key :stock_lots, :suppliers

    remove_foreign_key :facturas, :suppliers
    add_foreign_key :facturas, :suppliers

    remove_column :stock_lots, :supplier_name
    remove_column :facturas, :supplier_name

    raise ActiveRecord::IrreversibleMigration, "No se puede volver a supplier_id NOT NULL en facturas si ya existen facturas sin proveedor"
  end
end
