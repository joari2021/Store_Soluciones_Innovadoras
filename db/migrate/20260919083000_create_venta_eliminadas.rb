class CreateVentaEliminadas < ActiveRecord::Migration[7.0]
  def change
    create_table :venta_eliminadas do |t|
      t.integer :venta_id
      t.integer :business_id, null: false
      t.integer :seller_user_id
      t.integer :cashier_user_id
      t.integer :cliente_id
      t.jsonb :payload, default: {}
      t.decimal :total_usd, precision: 14, scale: 2
      t.decimal :total_bs, precision: 14, scale: 2
      t.integer :deleted_by_user_id
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :venta_eliminadas, :business_id
    add_index :venta_eliminadas, :venta_id
  end
end
