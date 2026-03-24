class AddAuthorizationLevelToUsers < ActiveRecord::Migration[7.1]
  def up
    unless column_exists?(:users, :authorization_level)
      add_column :users, :authorization_level, :string, null: false, default: 'standard_staff'
    end

    say_with_time 'Sincronizando nivel de autorizacion segun rol actual' do
      execute <<~SQL.squish
        UPDATE users
        SET authorization_level = CASE
          WHEN admin = TRUE THEN 'administrator'
          ELSE COALESCE(NULLIF(authorization_level, ''), 'standard_staff')
        END
      SQL
    end

    add_index :users, :authorization_level unless index_exists?(:users, :authorization_level)
  end

  def down
    remove_index :users, :authorization_level if index_exists?(:users, :authorization_level)
    remove_column :users, :authorization_level if column_exists?(:users, :authorization_level)
  end
end