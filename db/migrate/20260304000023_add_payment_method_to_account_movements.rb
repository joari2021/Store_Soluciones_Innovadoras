class AddPaymentMethodToAccountMovements < ActiveRecord::Migration[7.1]
  def change
    add_column :account_movements, :payment_method, :string
    add_index :account_movements, :payment_method
  end
end
