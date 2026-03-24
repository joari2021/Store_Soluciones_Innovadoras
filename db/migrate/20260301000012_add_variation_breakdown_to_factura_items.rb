class AddVariationBreakdownToFacturaItems < ActiveRecord::Migration[7.1]
  def change
    add_column :factura_items, :variation_breakdown, :jsonb, null: false, default: []
  end
end
