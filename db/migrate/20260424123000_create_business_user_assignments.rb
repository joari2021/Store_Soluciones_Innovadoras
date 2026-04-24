class CreateBusinessUserAssignments < ActiveRecord::Migration[7.1]
  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  def up
    create_table :business_user_assignments do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :authorization_level, null: false, default: 'standard_staff'
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :business_user_assignments, %i[business_id user_id], unique: true, name: 'idx_business_user_assignments_unique'
    add_index :business_user_assignments, %i[user_id active], name: 'idx_business_user_assignments_user_active'

    backfill_assignments!
  end

  def down
    drop_table :business_user_assignments
  end

  private

  def backfill_assignments!
    say_with_time 'Backfilling business user assignments from users.business_id' do
      MigrationUser.where.not(business_id: nil).find_each do |user|
        level = if user.respond_to?(:admin?) && user.admin?
                  'administrator'
                elsif user.respond_to?(:authorization_level) && user.authorization_level.to_s == 'manager'
                  'manager'
                else
                  'standard_staff'
                end

        execute <<~SQL.squish
          INSERT INTO business_user_assignments (business_id, user_id, authorization_level, active, created_at, updated_at)
          VALUES (#{user.business_id.to_i}, #{user.id.to_i}, #{ActiveRecord::Base.connection.quote(level)}, TRUE, NOW(), NOW())
          ON CONFLICT (business_id, user_id) DO NOTHING
        SQL
      end
    end
  end
end
