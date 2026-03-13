class RemoveUnidadesFromFacturaItems < ActiveRecord::Migration[7.0]
  def change
    remove_column :factura_items, :unidades, :string
  end
end
