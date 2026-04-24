class AddCustomerModeFields < ActiveRecord::Migration[7.1]
  def change
    add_column :business_user_assignments, :customer_access_level, :string, null: false, default: "none"
    add_index :business_user_assignments, :customer_access_level

    add_reference :clientes, :user, foreign_key: true
    add_index :clientes, [:business_id, :user_id], unique: true, where: "user_id IS NOT NULL"

    add_column :venta_payments, :pending_validation, :boolean, null: false, default: false
    add_index :venta_payments, :pending_validation
  end
end
