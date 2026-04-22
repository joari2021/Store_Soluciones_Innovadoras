class CreateGlobalCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :global_categories do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :global_categories, :name, unique: true
  end
end
