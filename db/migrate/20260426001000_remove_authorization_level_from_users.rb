class RemoveAuthorizationLevelFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_index :users, :authorization_level if index_exists?(:users, :authorization_level)
    remove_column :users, :authorization_level if column_exists?(:users, :authorization_level)
  end
end
