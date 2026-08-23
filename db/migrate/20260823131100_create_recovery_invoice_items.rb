class CreateRecoveryInvoiceItems < ActiveRecord::Migration[7.1]
  def change
    create_table :recovery_invoice_items do |t|
      t.references :recovery_invoice, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.references :product_variation, null: true, foreign_key: { to_table: :product_variations }
      t.decimal :quantity, precision: 12, scale: 3, null: false, default: 0
      t.decimal :unit_price_usd, precision: 14, scale: 2, null: false, default: 0.0
      t.decimal :total_price_usd, precision: 14, scale: 2, null: false, default: 0.0

      t.timestamps
    end
  end
end
