class AddCashierUserToVentas < ActiveRecord::Migration[7.1]
  def change
    add_reference :ventas, :cashier_user, foreign_key: { to_table: :users }, index: true
  end
end
