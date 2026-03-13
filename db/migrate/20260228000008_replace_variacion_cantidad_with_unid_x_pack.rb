class ReplaceVariacionCantidadWithUnidXPack < ActiveRecord::Migration[7.1]
  def up
    if column_exists?(:factura_items, :variacion_cantidad)
      rename_column :factura_items, :variacion_cantidad, :unid_x_pack
    end

    if column_exists?(:supplier_products, :variacion_cantidad)
      remove_column :supplier_products, :variacion_cantidad, :decimal
    end
  end

  def down
    if column_exists?(:factura_items, :unid_x_pack)
      rename_column :factura_items, :unid_x_pack, :variacion_cantidad
    end

    unless column_exists?(:supplier_products, :variacion_cantidad)
      add_column :supplier_products, :variacion_cantidad, :decimal, precision: 12, scale: 4
    end
  end
end
