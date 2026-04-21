class AddDeliveredToPurchaseInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :facturas, :delivered, :boolean, null: false, default: true
    add_index :facturas, :delivered
  end
end
