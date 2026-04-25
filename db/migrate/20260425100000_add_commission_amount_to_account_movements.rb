class AddCommissionAmountToAccountMovements < ActiveRecord::Migration[7.1]
  def change
    add_column :account_movements, :commission_amount, :decimal, precision: 14, scale: 2
  end
end
