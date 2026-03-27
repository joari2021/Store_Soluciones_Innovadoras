class AddCashRoleToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :cash_role, :string
    add_index :accounts, :cash_role

    Account.reset_column_information

    Account.find_each do |account|
      if account.account_type == 'cash_box'
        inferred_role = account.name.to_s.downcase.include?('deposito') ? 'cash_deposit' : 'cash_box'
        account.update_columns(cash_role: inferred_role)
      else
        account.update_columns(cash_role: nil)
      end
    end
  end

  def down
    remove_index :accounts, :cash_role
    remove_column :accounts, :cash_role
  end
end
