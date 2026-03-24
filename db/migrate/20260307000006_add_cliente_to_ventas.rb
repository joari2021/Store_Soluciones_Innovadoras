class AddClienteToVentas < ActiveRecord::Migration[7.1]
  def change
    add_reference :ventas, :cliente, foreign_key: true
  end
end
