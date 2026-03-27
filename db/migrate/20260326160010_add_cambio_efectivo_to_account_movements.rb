class AddCambioEfectivoToAccountMovements < ActiveRecord::Migration[7.1]
  def change
    add_reference :account_movements, :cambio_efectivo, foreign_key: true, index: true
  end
end
