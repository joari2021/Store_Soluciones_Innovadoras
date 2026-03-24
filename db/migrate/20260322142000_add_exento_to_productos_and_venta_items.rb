class AddExentoToProductosAndVentaItems < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :exento, :boolean, default: false, null: false unless column_exists?(:productos, :exento)

    return if column_exists?(:venta_items, :exento)

    add_column :venta_items, :exento, :boolean, default: false, null: false
  end
end
