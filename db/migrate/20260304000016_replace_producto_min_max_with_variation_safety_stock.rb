class ReplaceProductoMinMaxWithVariationSafetyStock < ActiveRecord::Migration[7.1]
  def change
    remove_column :productos, :min_stock, :integer if column_exists?(:productos, :min_stock)
    remove_column :productos, :max_stock, :integer if column_exists?(:productos, :max_stock)

    unless column_exists?(:product_variations, :safety_stock)
      add_column :product_variations, :safety_stock, :decimal, precision: 12, scale: 4, null: false, default: 0
    end
  end
end
