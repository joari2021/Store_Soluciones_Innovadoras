class CreateVideoDetails < ActiveRecord::Migration[7.1]
  def change
    create_table :video_details do |t|
      t.string :calidad
      t.string :audio
      t.string :peso
      t.string :formato
      t.string :resolucion
      t.string :subtitulos
      t.references :pelicula, null: false, foreign_key: true

      t.timestamps
    end
  end
end
