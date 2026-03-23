class AddContactFieldsToBusinesses < ActiveRecord::Migration[7.1]
  def up
    add_column :businesses, :phone, :string unless column_exists?(:businesses, :phone)
    add_column :businesses, :address, :text unless column_exists?(:businesses, :address)
    add_column :businesses, :rif, :string unless column_exists?(:businesses, :rif)
  end

  def down
    remove_column :businesses, :rif if column_exists?(:businesses, :rif)
    remove_column :businesses, :address if column_exists?(:businesses, :address)
    remove_column :businesses, :phone if column_exists?(:businesses, :phone)
  end
end
