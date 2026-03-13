class RemoveExistenciaFromProductos < ActiveRecord::Migration[7.1]
  def change
    remove_column :productos, :existencia, :integer
  end
end
