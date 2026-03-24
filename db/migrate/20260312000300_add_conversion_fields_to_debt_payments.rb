class AddConversionFieldsToDebtPayments < ActiveRecord::Migration[7.1]
  def up
    add_column :debt_payments, :exchange_rate_to_debt_currency, :decimal,
               precision: 20, scale: 8, null: false, default: 1
    add_column :debt_payments, :amount_in_debt_currency, :decimal,
               precision: 14, scale: 2, null: false, default: 0

    add_index :debt_payments, :currency

    execute <<~SQL.squish
      UPDATE debt_payments
      SET amount_in_debt_currency = amount,
          exchange_rate_to_debt_currency = 1
    SQL
  end

  def down
    remove_index :debt_payments, :currency
    remove_column :debt_payments, :amount_in_debt_currency
    remove_column :debt_payments, :exchange_rate_to_debt_currency
  end
end
