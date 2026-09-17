class AddCommissionFieldsToDebtPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :debt_payments, :include_commission, :boolean, null: false, default: false
    add_column :debt_payments, :commission_amount, :decimal, precision: 14, scale: 2, null: false, default: 0
  end
end
