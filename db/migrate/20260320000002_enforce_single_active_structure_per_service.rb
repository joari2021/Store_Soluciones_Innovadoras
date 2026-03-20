class EnforceSingleActiveStructurePerService < ActiveRecord::Migration[7.1]
  class MigrationServiceExpenseStructure < ApplicationRecord
    self.table_name = "service_expense_structures"
  end

  def up
    normalize_active_structures!

    add_index :service_expense_structures,
              :service_id,
              unique: true,
              where: "active_for_sales = TRUE",
              name: "idx_service_exp_structures_active_sale_unique"
  end

  def down
    remove_index :service_expense_structures,
                 name: "idx_service_exp_structures_active_sale_unique"
  end

  private

  def normalize_active_structures!
    grouped_rows = MigrationServiceExpenseStructure
      .order(:service_id, :id)
      .pluck(:id, :service_id, :active_for_sales)
      .group_by { |(_id, service_id, _active)| service_id }

    grouped_rows.each_value do |rows|
      active_rows = rows.select { |(_id, _service_id, active)| ActiveModel::Type::Boolean.new.cast(active) }
      next if active_rows.size <= 1

      keep_id = active_rows.first.first

      active_rows.each do |row_id, _service_id, _active|
        next if row_id == keep_id

        MigrationServiceExpenseStructure.where(id: row_id).update_all(active_for_sales: false)
      end
    end
  end
end
