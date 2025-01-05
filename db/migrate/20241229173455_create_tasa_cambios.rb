class CreateTasaCambios < ActiveRecord::Migration[7.1]
  def change
    create_table :tasa_cambios do |t|
      t.decimal :valor

      t.timestamps
    end
  end
end
