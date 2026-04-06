class AddStockLotBreakdownToProductUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :product_usages, :stock_lot_breakdown, :jsonb, default: [], null: false
  end
end
