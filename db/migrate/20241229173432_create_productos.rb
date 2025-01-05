class CreateProductos < ActiveRecord::Migration[7.1]
  def change
    create_table :productos do |t|
      t.text :descripcion
      t.decimal :precio_costo
      t.decimal :precio_venta
      t.integer :cant_unidades
      t.string :nivel_ganancia

      t.timestamps
    end
  end
end
