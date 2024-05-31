class CreateGenerosPeliculas < ActiveRecord::Migration[7.1]
  def change
    create_table :generos_peliculas do |t|
      t.references :pelicula, null: false, foreign_key: true
      t.references :genero, null: false, foreign_key: true

      t.timestamps
    end
  end
end
