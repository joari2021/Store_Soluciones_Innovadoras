class AddCampoToUser < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :personal, :boolean, default: false
  end
end
