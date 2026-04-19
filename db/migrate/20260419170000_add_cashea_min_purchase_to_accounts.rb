class AddCasheaMinPurchaseToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :cashea_min_purchase_usd, :decimal, precision: 14, scale: 2, default: 0.0, null: false
  end
end
