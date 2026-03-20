class AddPaymentDateToVentaPayments < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:venta_payments, :payment_date)

    add_column :venta_payments, :payment_date, :date
    add_index :venta_payments,
              %i[account_id reference payment_date],
              name: 'index_venta_payments_on_account_reference_payment_date'
  end
end
