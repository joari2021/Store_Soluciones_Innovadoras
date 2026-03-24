class AddBusinessAndProfileFieldsToUsers < ActiveRecord::Migration[7.1]
  def up
    add_reference :users, :business, foreign_key: true
    add_column :users, :full_name, :string
    add_column :users, :active, :boolean, null: false, default: true

    first_business_id = select_value('SELECT id FROM businesses ORDER BY id ASC LIMIT 1')
    if first_business_id.present?
      execute("UPDATE users SET business_id = #{first_business_id.to_i} WHERE business_id IS NULL")
    end
  end

  def down
    remove_column :users, :active
    remove_column :users, :full_name
    remove_reference :users, :business, foreign_key: true
  end
end
