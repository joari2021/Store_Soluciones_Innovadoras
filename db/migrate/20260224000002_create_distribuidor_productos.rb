class CreateDistribuidorProductos < ActiveRecord::Migration[7.0]
  def change
    create_table :distribuidor_productos do |t|
      t.bigint :distribuidor_id, null: false
      t.references :producto, null: false, foreign_key: true

      t.decimal :costo_mayor, precision: 12, scale: 4
      t.decimal :cantidad, precision: 12, scale: 4
      t.string :unidades
      t.decimal :costo_menor, precision: 12, scale: 4
      t.string :variacion_nombre
      t.decimal :variacion_cantidad, precision: 12, scale: 4

      t.timestamps
    end

    add_foreign_key :distribuidor_productos, :distribuidores, column: :distribuidor_id
    add_index :distribuidor_productos, [:distribuidor_id, :producto_id], name: "index_distribuidor_producto_on_distribuidor_producto", unique: false
  end
end
