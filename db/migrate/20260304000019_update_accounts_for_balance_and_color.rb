class UpdateAccountsForBalanceAndColor < ActiveRecord::Migration[7.1]
  def change
    remove_column :accounts, :institution, :string if column_exists?(:accounts, :institution)
    remove_column :accounts, :identifier, :string if column_exists?(:accounts, :identifier)

    unless column_exists?(:accounts, :balance)
      add_column :accounts, :balance, :decimal, precision: 14, scale: 2, null: false, default: 0
    end

    unless column_exists?(:accounts, :theme_color)
      add_column :accounts, :theme_color, :string, null: false, default: 'sky'
    end

    add_index :accounts, :theme_color unless index_exists?(:accounts, :theme_color)
  end
end
