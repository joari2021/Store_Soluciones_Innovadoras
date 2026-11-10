class CreateCasheaUserFinancings < ActiveRecord::Migration[7.1]
  def change
    create_table :cashea_user_financings do |t|
      t.references :business, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :user_name, null: false
      t.string :line_mode, null: false
      t.decimal :initial_ficticia_usd, precision: 14, scale: 2, null: false, default: 0
      t.string :payable_group_token, null: false
      t.string :receivable_group_token, null: false
      t.jsonb :installments, null: false, default: []

      t.timestamps
    end

    add_index :cashea_user_financings, [:business_id, :created_at], name: 'idx_cashea_user_financing_business_created_at'
    add_index :cashea_user_financings, [:business_id, :payable_group_token], name: 'idx_cashea_user_financing_payable_group'
    add_index :cashea_user_financings, [:business_id, :receivable_group_token], name: 'idx_cashea_user_financing_receivable_group'
  end
end
