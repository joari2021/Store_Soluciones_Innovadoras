class CreateAnimes < ActiveRecord::Migration[7.1]
  def change
    create_table :animes do |t|
      t.string :poster
      t.string :name
      t.integer :year
      t.integer :temporadas
      t.integer :capitulos
      t.text :sinopsis
      t.string :audio
      t.string :calidad
      t.string :formato_video
      t.string :codigo

      t.timestamps
    end
  end
end
