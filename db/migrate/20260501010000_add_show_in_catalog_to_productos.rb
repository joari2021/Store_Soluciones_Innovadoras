class AddShowInCatalogToProductos < ActiveRecord::Migration[7.1]
  def up
    add_column :productos, :show_in_catalog, :boolean, default: true, null: false
    execute <<~SQL
      UPDATE productos
      SET show_in_catalog = TRUE
      WHERE show_in_catalog IS NULL
    SQL
  end

  def down
    remove_column :productos, :show_in_catalog
  end
end
