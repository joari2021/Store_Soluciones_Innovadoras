class CreatePlataformaPeliculas < ActiveRecord::Migration[7.1]
  def change
    create_table :plataforma_peliculas do |t|
      t.string :name
      t.integer :escala

      t.timestamps
    end
  end
end
