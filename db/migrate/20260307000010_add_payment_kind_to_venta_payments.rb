class AddPaymentKindToVentaPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :venta_payments, :payment_kind, :string, null: false, default: 'in'
    add_index :venta_payments, :payment_kind
  end
end
