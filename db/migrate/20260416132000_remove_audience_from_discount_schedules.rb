class RemoveAudienceFromDiscountSchedules < ActiveRecord::Migration[7.1]
  class MigrationDiscountSchedule < ApplicationRecord
    self.table_name = 'discount_schedules'
  end

  def up
    MigrationDiscountSchedule.reset_column_information

    MigrationDiscountSchedule.find_each do |row|
      applies_to = row.applies_to.to_s
      next if %w[products services].include?(applies_to)

      product_ids = Array(row.product_ids).compact
      service_ids = Array(row.service_ids).compact

      if service_ids.any? && product_ids.blank?
        row.update_columns(applies_to: 'services')
      else
        row.update_columns(applies_to: 'products', service_ids: [])
      end
    end

    remove_column :discount_schedules, :audience, :string
    change_column_default :discount_schedules, :applies_to, from: 'both', to: 'products'
  end

  def down
    add_column :discount_schedules, :audience, :string, default: 'all_clients', null: false
    change_column_default :discount_schedules, :applies_to, from: 'products', to: 'both'
  end
end