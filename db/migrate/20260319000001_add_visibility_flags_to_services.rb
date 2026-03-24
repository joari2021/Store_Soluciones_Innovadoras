class AddVisibilityFlagsToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :caution_service, :boolean, default: false, null: false
    add_column :services, :restricted_service, :boolean, default: false, null: false

    add_index :services, :caution_service
    add_index :services, :restricted_service
  end
end
