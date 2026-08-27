class AddTrigramIndexToProductosDescripcion < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_productos_on_lower_descripcion_trgm
      ON productos
      USING gin (LOWER(descripcion) gin_trgm_ops);
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_productos_on_lower_descripcion_trgm;
    SQL
  end
end
