class CreateLossRecoverySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :loss_recovery_settings do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: false
      t.decimal :surcharge_percent, precision: 8, scale: 4, null: false, default: 0
      t.decimal :min_invoice_total_usd, precision: 12, scale: 2, null: false, default: 5

      t.timestamps
    end
  end
end
