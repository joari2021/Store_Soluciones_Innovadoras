class AddRequiredQuantityToServicePrintMaterialSurcharges < ActiveRecord::Migration[7.1]
  def change
    add_column :service_print_material_surcharges,
               :required_quantity,
               :decimal,
               precision: 12,
               scale: 2,
               null: false,
               default: 1.0
  end
end
