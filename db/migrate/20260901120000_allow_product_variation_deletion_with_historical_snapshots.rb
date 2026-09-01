class AllowProductVariationDeletionWithHistoricalSnapshots < ActiveRecord::Migration[7.1]
  def up
    add_column :product_usages, :variation_name, :string unless column_exists?(:product_usages, :variation_name)
    add_column :recovery_invoice_items, :variation_name, :string unless column_exists?(:recovery_invoice_items, :variation_name)
    add_column :pack_unwrap_items, :source_variation_name, :string unless column_exists?(:pack_unwrap_items, :source_variation_name)
    add_column :pack_unwrap_items, :destination_variation_name, :string unless column_exists?(:pack_unwrap_items, :destination_variation_name)

    execute <<~SQL.squish
      UPDATE product_usages
      SET variation_name = product_variations.description
      FROM product_variations
      WHERE product_usages.product_variation_id = product_variations.id
        AND (product_usages.variation_name IS NULL OR product_usages.variation_name = '')
    SQL

    execute <<~SQL.squish
      UPDATE recovery_invoice_items
      SET variation_name = product_variations.description
      FROM product_variations
      WHERE recovery_invoice_items.product_variation_id = product_variations.id
        AND (recovery_invoice_items.variation_name IS NULL OR recovery_invoice_items.variation_name = '')
    SQL

    execute <<~SQL.squish
      UPDATE pack_unwrap_items
      SET source_variation_name = product_variations.description
      FROM product_variations
      WHERE pack_unwrap_items.source_product_variation_id = product_variations.id
        AND (pack_unwrap_items.source_variation_name IS NULL OR pack_unwrap_items.source_variation_name = '')
    SQL

    execute <<~SQL.squish
      UPDATE pack_unwrap_items
      SET destination_variation_name = product_variations.description
      FROM product_variations
      WHERE pack_unwrap_items.destination_product_variation_id = product_variations.id
        AND (pack_unwrap_items.destination_variation_name IS NULL OR pack_unwrap_items.destination_variation_name = '')
    SQL

    change_column_null :product_usages, :product_variation_id, true
    change_column_null :pack_unwrap_items, :source_product_variation_id, true
    change_column_null :pack_unwrap_items, :destination_product_variation_id, true

    replace_variation_foreign_key(:product_usages, :product_variation_id)
    replace_variation_foreign_key(:recovery_invoice_items, :product_variation_id)
    replace_variation_foreign_key(:stock_lot_variations, :product_variation_id)
    replace_variation_foreign_key(:venta_items, :product_variation_id)
    replace_variation_foreign_key(:service_product_expenses, :product_variation_id)
    replace_variation_foreign_key(:pack_unwrap_items, :source_product_variation_id)
    replace_variation_foreign_key(:pack_unwrap_items, :destination_product_variation_id)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Historical variation references were intentionally detached.'
  end

  private

  def replace_variation_foreign_key(table, column)
    remove_foreign_key table, :product_variations, column: column if foreign_key_exists?(table, :product_variations, column: column)
    add_foreign_key table, :product_variations, column: column, on_delete: :nullify
  end
end
