class AddReferenceToAccountMovements < ActiveRecord::Migration[7.1]
  def change
    add_column :account_movements, :reference, :string
    add_index :account_movements, :reference
  end
end
