class AddPrintDeliveryExtraProductsToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :print_delivery_extra_products, :jsonb, default: [], null: false
  end
end
