class AddTrigramIndexesToServicesSearch < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_services_on_lower_description_trgm
      ON services
      USING gin (LOWER(description) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_system_services_on_lower_name_trgm
      ON system_services
      USING gin (LOWER(name) gin_trgm_ops);
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_services_on_lower_description_trgm;
    SQL

    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_system_services_on_lower_name_trgm;
    SQL
  end
end
