class AddBusinessToServices < ActiveRecord::Migration[7.1]
  class MigrationBusiness < ApplicationRecord
    self.table_name = 'businesses'
  end

  def up
    return if column_exists?(:services, :business_id)

    add_reference :services, :business, foreign_key: true

    business_id = ensure_default_business_id
    execute("UPDATE services SET business_id = #{business_id} WHERE business_id IS NULL")

    change_column_null :services, :business_id, false
  end

  def down
    remove_reference :services, :business, foreign_key: true if column_exists?(:services, :business_id)
  end

  private

  def ensure_default_business_id
    existing_id = MigrationBusiness.order(:id).limit(1).pick(:id)
    return existing_id.to_i if existing_id.present?

    MigrationBusiness.create!(name: 'Principal').id
  end
end
