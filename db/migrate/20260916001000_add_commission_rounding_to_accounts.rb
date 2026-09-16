class AddCommissionRoundingToAccounts < ActiveRecord::Migration[7.0]
  def change
    change_table :accounts, bulk: true do |t|
      t.string :send_commission_rounding, default: 'superior', null: false
      t.string :receive_commission_rounding, default: 'superior', null: false
    end
  end
end
