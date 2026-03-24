class AddIncludeProductPriceInSaleToServicePrintMaterialSurcharges < ActiveRecord::Migration[7.1]
  def change
    add_column :service_print_material_surcharges,
               :include_product_price_in_sale,
               :boolean,
               default: false,
               null: false

    add_index :service_print_material_surcharges,
              :include_product_price_in_sale,
              name: 'idx_print_material_include_product_price'
  end
end
