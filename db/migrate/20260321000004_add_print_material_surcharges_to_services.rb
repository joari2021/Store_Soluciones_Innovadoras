class AddPrintMaterialSurchargesToServices < ActiveRecord::Migration[7.1]
  def change
    create_table :service_print_material_surcharges do |t|
      t.references :service, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.decimal :surcharge_percent, precision: 7, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :service_print_material_surcharges,
              %i[service_id producto_id],
              unique: true,
              name: 'idx_service_print_material_surcharges_unique'
  end
end
