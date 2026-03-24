class AddAutoCostStockDiscountToServicesAndDebts < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :auto_cost_stock_discount, :boolean, default: false, null: false
    add_index :services, :auto_cost_stock_discount

    add_column :debts, :service_cost_pending, :boolean, default: false, null: false
    add_reference :debts, :venta, foreign_key: { to_table: :ventas, on_delete: :nullify }
    add_reference :debts, :service, foreign_key: { on_delete: :nullify }
    add_index :debts, %i[service_cost_pending debt_kind], name: 'index_debts_on_service_cost_pending_and_kind'
  end
end
