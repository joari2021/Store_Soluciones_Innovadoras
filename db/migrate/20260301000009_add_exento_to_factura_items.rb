class AddExentoToFacturaItems < ActiveRecord::Migration[7.1]
  def change
    add_column :factura_items, :exento, :boolean, default: false, null: false
  end
end
