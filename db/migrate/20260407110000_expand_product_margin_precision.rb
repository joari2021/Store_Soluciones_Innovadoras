class ExpandProductMarginPrecision < ActiveRecord::Migration[7.1]
  def up
    change_column :productos, :porcentaje_ganancia, :decimal, precision: 7, scale: 2
  end

  def down
    change_column :productos, :porcentaje_ganancia, :decimal, precision: 5, scale: 2
  end
end
