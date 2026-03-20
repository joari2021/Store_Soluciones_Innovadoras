class AddThemeProfileToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :theme_profile, :string, null: false, default: 'neon_blue'
    add_index :businesses, :theme_profile
  end
end
