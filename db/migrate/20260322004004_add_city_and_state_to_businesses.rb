class AddCityAndStateToBusinesses < ActiveRecord::Migration[7.1]
  def up
    add_column :businesses, :city, :string unless column_exists?(:businesses, :city)
    add_column :businesses, :state, :string unless column_exists?(:businesses, :state)
  end

  def down
    remove_column :businesses, :state if column_exists?(:businesses, :state)
    remove_column :businesses, :city if column_exists?(:businesses, :city)
  end
end
