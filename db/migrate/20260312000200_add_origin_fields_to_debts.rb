class AddOriginFieldsToDebts < ActiveRecord::Migration[7.1]
  def change
    add_column :debts, :origin_kind, :string, null: false, default: 'general'
    add_reference :debts, :loan_account, foreign_key: { to_table: :accounts }

    add_index :debts, :origin_kind
  end
end
