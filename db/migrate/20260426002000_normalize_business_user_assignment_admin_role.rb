class NormalizeBusinessUserAssignmentAdminRole < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE business_user_assignments
      SET authorization_level = 'manager'
      WHERE authorization_level = 'administrator'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE business_user_assignments
      SET authorization_level = 'administrator'
      WHERE authorization_level = 'manager'
    SQL
  end
end
