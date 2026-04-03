class RemoveUniqueIndexFromPrintMaterialSurcharges < ActiveRecord::Migration[7.1]
  UNIQUE_INDEX_NAME = 'idx_service_print_material_surcharges_unique'.freeze
  NON_UNIQUE_INDEX_NAME = 'idx_service_print_material_surcharges_service_producto'.freeze

  def up
    remove_index :service_print_material_surcharges, name: UNIQUE_INDEX_NAME if index_name_exists?(:service_print_material_surcharges, UNIQUE_INDEX_NAME)

    add_index :service_print_material_surcharges,
              %i[service_id producto_id],
              name: NON_UNIQUE_INDEX_NAME unless index_name_exists?(:service_print_material_surcharges, NON_UNIQUE_INDEX_NAME)
  end

  def down
    remove_index :service_print_material_surcharges, name: NON_UNIQUE_INDEX_NAME if index_name_exists?(:service_print_material_surcharges, NON_UNIQUE_INDEX_NAME)

    add_index :service_print_material_surcharges,
              %i[service_id producto_id],
              unique: true,
              name: UNIQUE_INDEX_NAME unless index_name_exists?(:service_print_material_surcharges, UNIQUE_INDEX_NAME)
  end

  private

  def index_name_exists?(table_name, index_name)
    connection.indexes(table_name).any? { |index| index.name == index_name }
  end
end
