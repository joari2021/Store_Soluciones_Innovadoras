class CreateServicePrintVolumeDiscounts < ActiveRecord::Migration[7.1]
  def change
    create_table :service_print_volume_discounts do |t|
      t.references :service, null: false, foreign_key: true
      t.integer :min_quantity, null: false
      t.decimal :discount_percent, precision: 5, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :service_print_volume_discounts, [:service_id, :min_quantity], name: 'idx_service_print_volume_discounts_on_service_min_qty'
  end
end
