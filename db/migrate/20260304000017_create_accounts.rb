class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :account_type, null: false
      t.string :currency, null: false
      t.string :institution
      t.string :identifier
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :accounts, :account_type
    add_index :accounts, :currency
    add_index :accounts, :active
  end
end
