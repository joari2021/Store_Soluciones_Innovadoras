class AddPrintDeliveryMaterialSurchargeToServices < ActiveRecord::Migration[7.1]
  def change
    add_reference :services,
                  :print_delivery_material_surcharge,
                  foreign_key: { to_table: :service_print_material_surcharges },
                  index: { name: 'index_services_on_print_delivery_material_surcharge_id' }
  end
end
