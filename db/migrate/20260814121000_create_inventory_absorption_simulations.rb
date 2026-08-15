class CreateInventoryAbsorptionSimulations < ActiveRecord::Migration[7.1]
  def change
    create_table :inventory_absorption_simulations do |t|
      t.references :destination_business, null: false, foreign_key: { to_table: :businesses }, index: true
      t.references :source_business, null: false, foreign_key: { to_table: :businesses }, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.string :mode, null: false
      t.datetime :simulated_at, null: false
      t.jsonb :summary, null: false, default: {}
      t.jsonb :preview, null: false, default: {}

      t.timestamps
    end

    add_index :inventory_absorption_simulations, [:destination_business_id, :created_at], name: 'idx_absorption_simulations_destination_created'
    add_index :inventory_absorption_simulations, [:source_business_id, :created_at], name: 'idx_absorption_simulations_source_created'
    add_index :inventory_absorption_simulations, :mode
  end
end
