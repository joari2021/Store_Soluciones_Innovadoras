class CreateBeerTicketSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :beer_ticket_settings do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.integer :next_serial, null: false, default: 1

      t.timestamps
    end

    create_table :beer_ticket_setting_products do |t|
      t.references :beer_ticket_setting, null: false, foreign_key: true, index: { name: "idx_beer_ticket_setting_products_on_setting_id" }
      t.references :producto, null: false, foreign_key: true

      t.timestamps
    end

    add_index :beer_ticket_setting_products,
              [:beer_ticket_setting_id, :producto_id],
              unique: true,
              name: "idx_beer_ticket_setting_products_on_setting_and_producto"
  end
end
