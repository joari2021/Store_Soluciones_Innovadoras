class RemoveCostFromManagers < ActiveRecord::Migration[7.1]
  def change
    remove_column :managers, :cost, :float
  end
end
