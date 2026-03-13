class AddSettlementSupportToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_reference :accounts, :settlement_account, foreign_key: { to_table: :accounts }

    create_table :account_settlements do |t|
      t.references :account, null: false, foreign_key: true
      t.references :settlement_account, foreign_key: { to_table: :accounts }
      t.decimal :total_amount, precision: 14, scale: 2, null: false
      t.integer :movements_count, null: false, default: 0
      t.datetime :closed_at, null: false
      t.datetime :period_start_at
      t.datetime :period_end_at
      t.decimal :credited_amount, precision: 14, scale: 2
      t.decimal :commission_amount, precision: 14, scale: 2
      t.datetime :processed_at
      t.date :settlement_date

      t.timestamps
    end

    add_index :account_settlements, %i[account_id processed_at]

    add_reference :account_movements, :account_settlement, foreign_key: true
  end
end
