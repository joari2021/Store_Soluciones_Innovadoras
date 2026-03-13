class AddFechaReferenciaToTasaCambios < ActiveRecord::Migration[7.1]
  def up
    add_column :tasa_cambios, :fecha_referencia, :date

    execute <<~SQL
      UPDATE tasa_cambios
      SET fecha_referencia = COALESCE(DATE(updated_at), DATE(created_at), CURRENT_DATE)
      WHERE fecha_referencia IS NULL;
    SQL

    change_column_null :tasa_cambios, :fecha_referencia, false
    add_index :tasa_cambios, [:description, :fecha_referencia]
  end

  def down
    remove_index :tasa_cambios, [:description, :fecha_referencia]
    remove_column :tasa_cambios, :fecha_referencia
  end
end
