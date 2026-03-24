class AddServiceCostDetailsAndProductVariationToServiceExpenses < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:debts, :service_cost_details)
      add_column :debts, :service_cost_details, :jsonb, default: {}, null: false
    end

    return if column_exists?(:service_product_expenses, :product_variation_id)

    add_reference :service_product_expenses, :product_variation, foreign_key: true
  end
end
