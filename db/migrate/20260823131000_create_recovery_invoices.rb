class CreateRecoveryInvoices < ActiveRecord::Migration[7.1]
  def change
    create_table :recovery_invoices do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: { to_table: :users }
      t.datetime :occurred_at, null: false
      t.decimal :total_usd, precision: 14, scale: 2, default: 0.0, null: false
      t.text :notes

      t.timestamps
    end
  end
end
