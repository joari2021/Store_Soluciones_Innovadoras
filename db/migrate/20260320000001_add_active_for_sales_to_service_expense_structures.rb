class AddActiveForSalesToServiceExpenseStructures < ActiveRecord::Migration[7.1]
  class MigrationServiceExpenseStructure < ApplicationRecord
    self.table_name = "service_expense_structures"
  end

  def up
    add_column :service_expense_structures, :active_for_sales, :boolean, default: false, null: false

    MigrationServiceExpenseStructure.update_all(active_for_sales: true)
  end

  def down
    remove_column :service_expense_structures, :active_for_sales
  end
end
