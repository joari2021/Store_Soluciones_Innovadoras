class AddSymbolToTasaCambios < ActiveRecord::Migration[7.1]
  def up
    add_column :tasa_cambios, :symbol, :string

    execute <<~SQL
      UPDATE tasa_cambios
      SET symbol = CASE COALESCE(NULLIF(TRIM(description), ''), '')
        WHEN 'Dolar BCV' THEN '$'
        WHEN 'Euro BCV' THEN '€'
        WHEN 'Unidad VI' THEN 'Bs'
        ELSE COALESCE(NULLIF(TRIM(description), ''), 'N/A')
      END
      WHERE symbol IS NULL OR symbol = '';
    SQL

    change_column_null :tasa_cambios, :symbol, false, 'N/A'
  end

  def down
    remove_column :tasa_cambios, :symbol
  end
end
