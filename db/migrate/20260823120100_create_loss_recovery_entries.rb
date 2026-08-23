class CreateLossRecoveryEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :loss_recovery_entries do |t|
      t.references :business, null: false, foreign_key: true
      t.references :venta, null: false, foreign_key: { to_table: :ventas }, index: { unique: true }
      t.references :account, null: true, foreign_key: true

      t.datetime :occurred_at, null: false
      t.string :base_currency, null: false
      t.decimal :tasa_dolar, precision: 14, scale: 4, null: false, default: 0
      t.decimal :real_total_base, precision: 14, scale: 2, null: false, default: 0
      t.decimal :charged_total_base, precision: 14, scale: 2, null: false, default: 0
      t.decimal :excess_base, precision: 14, scale: 2, null: false, default: 0
      t.decimal :real_total_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :charged_total_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :excess_usd, precision: 14, scale: 2, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :loss_recovery_entries, [:business_id, :occurred_at]
  end
end
