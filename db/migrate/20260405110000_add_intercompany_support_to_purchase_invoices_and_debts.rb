class AddIntercompanySupportToPurchaseInvoicesAndDebts < ActiveRecord::Migration[7.1]
  def change
    add_column :facturas, :intercompany, :boolean, default: false, null: false
    add_reference :facturas, :source_business, foreign_key: { to_table: :businesses }, null: true

    add_reference :debts, :mirror_debt, foreign_key: { to_table: :debts }, null: true
    add_reference :debts, :mirror_account, foreign_key: { to_table: :accounts }, null: true
    add_column :debts, :mirror_sync_enabled, :boolean, default: false, null: false

    add_reference :productos, :source_business, foreign_key: { to_table: :businesses }, null: true
    add_column :productos, :source_product_id, :bigint

    add_index :productos, [:business_id, :source_business_id, :source_product_id], unique: true,
              name: 'index_productos_on_business_and_source_product'
  end
end
