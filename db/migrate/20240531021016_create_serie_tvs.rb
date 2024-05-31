class CreateSerieTvs < ActiveRecord::Migration[7.1]
  def change
    create_table :serie_tvs do |t|
      t.string :poster
      t.string :name
      t.string :others_title
      t.integer :year
      t.integer :temporadas
      t.integer :capitulos
      t.string :director
      t.string :reparto
      t.text :sinopsis
      t.string :audio
      t.string :calidad
      t.string :status
      t.string :formato_video
      t.string :codigo

      t.timestamps
    end
  end
end
