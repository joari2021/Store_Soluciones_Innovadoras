class AddColumnAvailableToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :available, :boolean, default: true, null: false
  end
end
