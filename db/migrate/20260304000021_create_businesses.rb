class CreateBusinesses < ActiveRecord::Migration[7.1]
  def change
    create_table :businesses do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :businesses, :name
  end
end
