class ReplaceNivelGananciaWithPorcentaje < ActiveRecord::Migration[7.0]
  def change
    add_column :productos, :porcentaje_ganancia, :decimal, precision: 5, scale: 2
    remove_column :productos, :nivel_ganancia, :string
  end
end
