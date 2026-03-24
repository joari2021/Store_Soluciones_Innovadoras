class AddCostoMayorBsToFacturaItems < ActiveRecord::Migration[7.1]
  def up
    add_column :factura_items, :costo_mayor_bs, :decimal, precision: 14, scale: 4

    execute <<~SQL.squish
      UPDATE factura_items fi
      SET costo_mayor_bs = ROUND(COALESCE(fi.costo_mayor, 0) * COALESCE(f.tasa_dolar, 0), 4)
      FROM facturas f
      WHERE f.id = fi.factura_id
    SQL
  end

  def down
    remove_column :factura_items, :costo_mayor_bs
  end
end
