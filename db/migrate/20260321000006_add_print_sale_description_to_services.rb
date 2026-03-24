class AddPrintSaleDescriptionToServices < ActiveRecord::Migration[7.1]
  def up
    add_column :services, :print_sale_description, :string
    add_index :services, :print_sale_description

    execute <<~SQL
      UPDATE services
      SET print_sale_description = description
      WHERE (print_sale_description IS NULL OR print_sale_description = '')
        AND id IN (
          SELECT services.id
          FROM services
          INNER JOIN system_services ON system_services.id = services.system_service_id
          WHERE system_services.name ILIKE '%impresion%'
             OR system_services.name ILIKE '%impresión%'
        )
    SQL
  end

  def down
    remove_index :services, :print_sale_description
    remove_column :services, :print_sale_description
  end
end
