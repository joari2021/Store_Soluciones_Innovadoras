class CreateAccountMovements < ActiveRecord::Migration[7.1]
  def change
    create_table :account_movements do |t|
      t.references :account, null: false, foreign_key: true
      t.string :movement_kind, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.text :description
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :account_movements, [:account_id, :occurred_at]
    add_index :account_movements, :movement_kind
  end
end
