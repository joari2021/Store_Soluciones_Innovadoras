class AddCasheaPaymentMethodRestrictionsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :cashea_allow_pos, :boolean, default: true, null: false
    add_column :accounts, :cashea_allow_biopago, :boolean, default: true, null: false
  end
end
