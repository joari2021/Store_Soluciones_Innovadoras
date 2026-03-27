class CreateCambioEfectivos < ActiveRecord::Migration[7.1]
  def change
    create_table :cambio_efectivos do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :cash_shift, foreign_key: true
      t.decimal :efectivo_vendido, precision: 12, scale: 2, null: false
      t.decimal :monto_caja_operativa, precision: 12, scale: 2, null: false
      t.decimal :monto_caja_deposito, precision: 12, scale: 2, null: false
      t.decimal :monto_recibido, precision: 12, scale: 2, null: false
      t.decimal :recargo_percent, precision: 5, scale: 2, null: false
      t.string :payment_group, null: false
      t.string :currency, null: false, default: 'VES'
      t.jsonb :payment_details, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :cambio_efectivos, :occurred_at
  end
end
