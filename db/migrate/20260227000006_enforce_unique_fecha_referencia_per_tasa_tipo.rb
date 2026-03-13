class EnforceUniqueFechaReferenciaPerTasaTipo < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      DELETE FROM tasa_cambios
      WHERE description IN ('Dolar Paralelo', 'Dolar Promedio');
    SQL

    execute <<~SQL
      DELETE FROM tasa_cambios t1
      USING tasa_cambios t2
      WHERE t1.id < t2.id
        AND t1.description = t2.description
        AND t1.fecha_referencia = t2.fecha_referencia;
    SQL

    remove_index :tasa_cambios, [:description, :fecha_referencia] if index_exists?(:tasa_cambios, [:description, :fecha_referencia])
    add_index :tasa_cambios, [:description, :fecha_referencia], unique: true, name: "index_tasa_cambios_unique_desc_fecha_ref"
  end

  def down
    remove_index :tasa_cambios, name: "index_tasa_cambios_unique_desc_fecha_ref"
    add_index :tasa_cambios, [:description, :fecha_referencia]
  end
end
