class CreateDiscountSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :discount_schedules do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false, default: ''
      t.string :applies_to, null: false, default: 'both'
      t.jsonb :product_ids, null: false, default: []
      t.jsonb :service_ids, null: false, default: []
      t.string :quantity_mode, null: false, default: 'from_quantity'
      t.integer :quantity_threshold, null: false, default: 1
      t.string :discount_mode, null: false, default: 'percent'
      t.decimal :discount_value, precision: 12, scale: 2, null: false
      t.string :audience, null: false, default: 'all_clients'
      t.date :starts_on
      t.date :ends_on
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :discount_schedules, [:business_id, :active]
    add_index :discount_schedules, :starts_on
    add_index :discount_schedules, :ends_on
  end
end