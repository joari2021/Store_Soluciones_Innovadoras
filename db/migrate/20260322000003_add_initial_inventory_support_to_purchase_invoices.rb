class AddInitialInventorySupportToPurchaseInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :facturas, :invoice_kind, :string, null: false, default: 'purchase'
    add_index :facturas, :invoice_kind
    add_index :facturas,
              :business_id,
              unique: true,
              where: "invoice_kind = 'initial_inventory'",
              name: 'index_facturas_unique_initial_inventory_per_business'

    add_column :businesses, :hide_initial_inventory_button, :boolean, null: false, default: false

    add_column :stock_lots, :description, :string
    add_index :stock_lots, :description
  end
end
