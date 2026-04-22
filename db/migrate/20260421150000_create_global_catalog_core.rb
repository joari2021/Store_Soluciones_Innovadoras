class CreateGlobalCatalogCore < ActiveRecord::Migration[7.1]
  def change
    create_table :global_products do |t|
      t.string :name, null: false
      t.integer :presentation, null: false, default: 0
      t.integer :cant_presentation, null: false, default: 1
      t.boolean :exento, null: false, default: false
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.references :source_business, null: true, foreign_key: { to_table: :businesses }
      t.bigint :source_producto_id

      t.timestamps
    end

    add_index :global_products, :name
    add_index :global_products,
              [:source_business_id, :source_producto_id],
              unique: true,
              name: :index_global_products_on_source_business_and_producto

    create_table :global_suppliers do |t|
      t.string :name, null: false
      t.string :rif
      t.string :phone
      t.string :mobile_payment_phone
      t.string :email
      t.text :address
      t.string :bank_account_number
      t.string :pricing_currency_priority, null: false, default: "usd"
      t.boolean :default_exento, null: false, default: false
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.references :source_business, null: true, foreign_key: { to_table: :businesses }
      t.bigint :source_supplier_id

      t.timestamps
    end

    add_index :global_suppliers, :name
    add_index :global_suppliers,
              [:source_business_id, :source_supplier_id],
              unique: true,
              name: :index_global_suppliers_on_source_business_and_supplier

    create_table :global_supplier_products do |t|
      t.references :global_supplier, null: false, foreign_key: true
      t.references :global_product, null: false, foreign_key: true
      t.decimal :costo_mayor, precision: 12, scale: 2
      t.decimal :cantidad, precision: 12, scale: 2
      t.decimal :costo_menor, precision: 12, scale: 2
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :global_supplier_products,
              [:global_supplier_id, :global_product_id],
              unique: true,
              name: :index_global_supplier_products_unique_pair
  end
end
