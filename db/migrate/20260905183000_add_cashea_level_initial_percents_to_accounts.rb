class AddCasheaLevelInitialPercentsToAccounts < ActiveRecord::Migration[7.1]
  def change
    1.upto(6) do |level|
      add_column :accounts, "cashea_level_#{level}_initial_percent", :decimal, precision: 5, scale: 2, default: 0.0, null: false
    end
  end
end
