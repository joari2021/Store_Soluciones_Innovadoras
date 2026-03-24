class RemoveLegacyFieldsFromDebts < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :debts, :suppliers if foreign_key_exists?(:debts, :suppliers)
    remove_foreign_key :debts, column: :loan_account_id if foreign_key_exists?(:debts, column: :loan_account_id)

    remove_index :debts, :supplier_id if index_exists?(:debts, :supplier_id)
    remove_index :debts, :loan_account_id if index_exists?(:debts, :loan_account_id)
    remove_index :debts, :origin_kind if index_exists?(:debts, :origin_kind)

    remove_column :debts, :supplier_id, :bigint if column_exists?(:debts, :supplier_id)
    remove_column :debts, :loan_account_id, :bigint if column_exists?(:debts, :loan_account_id)
    remove_column :debts, :origin_kind, :string if column_exists?(:debts, :origin_kind)
    remove_column :debts, :reference, :string if column_exists?(:debts, :reference)
    remove_column :debts, :counterparty_name, :string if column_exists?(:debts, :counterparty_name)
  end

  def down
    add_column :debts, :origin_kind, :string, null: false, default: "general" unless column_exists?(:debts, :origin_kind)
    add_column :debts, :reference, :string unless column_exists?(:debts, :reference)
    add_column :debts, :counterparty_name, :string unless column_exists?(:debts, :counterparty_name)
    add_column :debts, :supplier_id, :bigint unless column_exists?(:debts, :supplier_id)
    add_column :debts, :loan_account_id, :bigint unless column_exists?(:debts, :loan_account_id)

    add_index :debts, :supplier_id unless index_exists?(:debts, :supplier_id)
    add_index :debts, :loan_account_id unless index_exists?(:debts, :loan_account_id)
    add_index :debts, :origin_kind unless index_exists?(:debts, :origin_kind)

    add_foreign_key :debts, :suppliers unless foreign_key_exists?(:debts, :suppliers)
    add_foreign_key :debts, :accounts, column: :loan_account_id unless foreign_key_exists?(:debts, column: :loan_account_id)
  end
end
