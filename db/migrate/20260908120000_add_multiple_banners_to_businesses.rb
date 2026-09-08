class AddMultipleBannersToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :banner_name, :string
    add_column :businesses, :banner_2_name, :string
    add_column :businesses, :banner_3_name, :string
  end
end
