class AddWarnDigitalOnlyDeliveryInSalesToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services,
               :warn_digital_only_delivery_in_sales,
               :boolean,
               null: false,
               default: false
  end
end
