class AddCasheaCommissionPercentToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :cashea_commission_percent, :decimal,
               precision: 5,
               scale: 2,
               default: 0,
               null: false
  end
end
