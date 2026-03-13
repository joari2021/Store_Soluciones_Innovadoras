class CreateScraperStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :scraper_statuses do |t|
      t.string :key, null: false
      t.boolean :healthy, null: false, default: true
      t.text :last_error_message
      t.datetime :last_error_at
      t.datetime :last_success_at

      t.timestamps
    end

    add_index :scraper_statuses, :key, unique: true
  end
end
