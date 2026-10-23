class AddBatchesToBeerTickets < ActiveRecord::Migration[7.1]
  def change
    add_column :beer_ticket_setting_products, :next_serial, :integer, null: false, default: 1

    create_table :beer_ticket_batches do |t|
      t.references :beer_ticket_setting_product, null: false, foreign_key: true, index: { name: 'idx_beer_ticket_batches_on_setting_product' }
      t.integer :start_serial, null: false
      t.integer :end_serial, null: false
      t.integer :ticket_count, null: false
      t.boolean :active, null: false, default: true
      t.datetime :printed_at

      t.timestamps
    end

    add_index :beer_ticket_batches, [:beer_ticket_setting_product_id, :created_at], name: 'idx_beer_ticket_batches_on_product_and_created_at'
  end
end
