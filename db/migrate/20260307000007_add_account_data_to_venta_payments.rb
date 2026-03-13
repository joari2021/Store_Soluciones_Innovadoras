class AddAccountDataToVentaPayments < ActiveRecord::Migration[7.1]
  def change
    add_reference :venta_payments, :account, foreign_key: true
    add_column :venta_payments, :currency, :string, null: false, default: 'USD'
    add_column :venta_payments, :amount_original, :decimal, precision: 14, scale: 2, null: false, default: 0
    add_column :venta_payments, :reference, :string

    add_index :venta_payments, :currency
  end
end
