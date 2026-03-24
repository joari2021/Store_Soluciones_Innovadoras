class AddPrintingDeliveryAndCoverageToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :delivery_physical_enabled, :boolean, default: false, null: false
    add_column :services, :delivery_digital_enabled, :boolean, default: false, null: false

    add_reference :services, :print_delivery_service, foreign_key: { to_table: :services }
    add_column :services, :print_delivery_pages, :jsonb, default: [], null: false

    create_table :service_print_coverage_prices do |t|
      t.references :service, null: false, foreign_key: true
      t.decimal :coverage_percent, precision: 5, scale: 2, null: false
      t.decimal :price_bs, precision: 14, scale: 2, null: false

      t.timestamps
    end

    add_index :service_print_coverage_prices, %i[service_id coverage_percent], unique: true,
                                                                               name: 'idx_print_coverage_unique'
  end
end
