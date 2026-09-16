class AddCommissionsToAccounts < ActiveRecord::Migration[7.0]
  def change
    change_table :accounts, bulk: true do |t|
      t.decimal :send_commission_percent, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :send_commission_min, precision: 14, scale: 2, default: 0.0, null: false
      t.decimal :receive_commission_percent, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :receive_commission_min, precision: 14, scale: 2, default: 0.0, null: false
    end
  end
end
