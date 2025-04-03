class AddPersonalSaimeToUser < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :personal_saime, :boolean, default: false, null: false
  end
end
