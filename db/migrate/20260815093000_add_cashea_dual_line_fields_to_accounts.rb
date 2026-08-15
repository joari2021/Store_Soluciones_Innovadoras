class AddCasheaDualLineFieldsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :cashea_principal_min_purchase_usd, :decimal, precision: 14, scale: 2, null: false, default: 0
    add_column :accounts, :cashea_cotidiana_category_ids, :jsonb, null: false, default: []
  end
end
