class AddLotBreakdownToRecoveryInvoiceItems < ActiveRecord::Migration[7.1]
  def change
    add_column :recovery_invoice_items, :lot_breakdown, :jsonb, default: []
    add_index :recovery_invoice_items, :lot_breakdown, using: :gin
  end
end
