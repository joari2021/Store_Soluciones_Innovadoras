class AddCamposToTables < ActiveRecord::Migration[7.1]
  def change
    add_column :tasa_cambios, :description, :string
    remove_column :services, :cost_price, :float
    remove_column :services, :currency_cost_price, :float
    rename_column :service_managers, :price, :cost
    add_column :service_managers, :reference_cost, :string
    add_column :service_managers, :symbol_tasa, :string
  end
end
