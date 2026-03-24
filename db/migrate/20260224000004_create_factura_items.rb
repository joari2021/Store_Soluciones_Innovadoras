class CreateFacturaItems < ActiveRecord::Migration[7.0]
  def change
    create_table :factura_items do |t|
      t.references :factura, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true

      t.decimal :costo_mayor, precision: 12, scale: 4
      t.decimal :cantidad, precision: 12, scale: 4
      t.string :unidades
      t.decimal :costo_menor, precision: 12, scale: 4
      t.string :variacion_nombre
      t.decimal :variacion_cantidad, precision: 12, scale: 4
      t.decimal :subtotal, precision: 14, scale: 4

      t.timestamps
    end
  end
end
