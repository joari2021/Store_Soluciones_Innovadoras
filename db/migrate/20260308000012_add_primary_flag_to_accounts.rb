class AddPrimaryFlagToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :is_primary, :boolean, default: false, null: false
    add_index :accounts, :business_id,
              unique: true,
              where: "account_type = 'bank_account' AND is_primary",
              name: 'index_accounts_primary_bank_per_business'
  end

  def down
    remove_index :accounts, name: 'index_accounts_primary_bank_per_business'
    remove_column :accounts, :is_primary
  end
end
