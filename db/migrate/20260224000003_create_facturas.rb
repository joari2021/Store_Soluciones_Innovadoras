class CreateFacturas < ActiveRecord::Migration[7.0]
  def change
    create_table :facturas do |t|
      t.bigint :distribuidor_id, null: false
      t.datetime :fecha_emision
      t.decimal :tasa_dolar, precision: 12, scale: 4
      t.decimal :monto_total, precision: 14, scale: 4
      t.string :numero
      t.text :observaciones

      t.timestamps
    end
    add_foreign_key :facturas, :distribuidores, column: :distribuidor_id
  end
end
