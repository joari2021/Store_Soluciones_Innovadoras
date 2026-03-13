class CreateVentaPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :venta_payments do |t|
      t.references :venta, null: false, foreign_key: { to_table: :ventas }
      t.string :payment_method, null: false
      t.decimal :amount_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amount_bs, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :venta_payments, :payment_method
  end
end
