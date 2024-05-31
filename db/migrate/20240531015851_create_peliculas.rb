class CreatePeliculas < ActiveRecord::Migration[7.1]
  def change
    create_table :peliculas do |t|
      t.string :poster
      t.string :name
      t.string :others_titles
      t.integer :year
      t.integer :duration_hours
      t.integer :duration_minutes
      t.string :director
      t.string :reparto
      t.text :sinopsis
      t.string :audio
      t.string :calidad
      t.string :formato_video
      t.string :codigo

      t.timestamps
    end
  end
end
