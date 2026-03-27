class AddRecargaFieldsToSystemServices < ActiveRecord::Migration[7.1]
  def change
    add_column :system_services, :recarga_min_amount, :decimal, precision: 12, scale: 2
    add_column :system_services, :recarga_multiple_amount, :decimal, precision: 12, scale: 2
    add_column :system_services, :recarga_profit_percent, :decimal, precision: 5, scale: 2
  end
end
