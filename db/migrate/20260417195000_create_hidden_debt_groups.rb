class CreateHiddenDebtGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :hidden_debt_groups do |t|
      t.references :business, null: false, foreign_key: true
      t.string :group_key, null: false
      t.datetime :hidden_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end

    add_index :hidden_debt_groups, [:business_id, :group_key], unique: true
  end
end
