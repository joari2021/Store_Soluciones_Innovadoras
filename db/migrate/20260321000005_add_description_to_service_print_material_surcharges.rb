class AddDescriptionToServicePrintMaterialSurcharges < ActiveRecord::Migration[7.1]
  def up
    add_column :service_print_material_surcharges, :description, :string
    add_index :service_print_material_surcharges, :description

    execute <<~SQL
      UPDATE service_print_material_surcharges
      SET description = productos.descripcion
      FROM productos
      WHERE productos.id = service_print_material_surcharges.producto_id
        AND (service_print_material_surcharges.description IS NULL OR service_print_material_surcharges.description = '')
    SQL
  end

  def down
    remove_index :service_print_material_surcharges, :description
    remove_column :service_print_material_surcharges, :description
  end
end
