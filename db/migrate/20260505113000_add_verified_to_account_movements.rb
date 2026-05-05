class AddVerifiedToAccountMovements < ActiveRecord::Migration[7.1]
  def change
    add_column :account_movements, :verified, :boolean, null: false, default: false
    add_index :account_movements, :verified
  end
end
