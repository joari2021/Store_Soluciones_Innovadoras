class AddColumnAvailableToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :productos, :available, :boolean, default: true, null: false
  end
end
