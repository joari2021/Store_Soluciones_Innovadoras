class CreateRequestedProductEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :requested_product_events do |t|
      t.references :business, null: false, foreign_key: true
      t.references :requested_product, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :user_name, null: false
      t.string :event_kind, null: false
      t.integer :requests_count_after, null: false

      t.timestamps
    end

    add_index :requested_product_events, %i[requested_product_id created_at], name: 'idx_requested_product_events_product_created_at'
    add_index :requested_product_events, :event_kind
  end
end
