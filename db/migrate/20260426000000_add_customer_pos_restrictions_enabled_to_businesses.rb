class AddCustomerPosRestrictionsEnabledToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :customer_pos_restrictions_enabled, :boolean, null: false, default: true
  end
end
