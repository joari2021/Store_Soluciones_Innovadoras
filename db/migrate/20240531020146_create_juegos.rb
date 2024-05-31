class CreateJuegos < ActiveRecord::Migration[7.1]
  def change
    create_table :juegos do |t|
      t.string :poster
      t.string :name
      t.integer :year
      t.string :desarrollador
      t.string :plataforma
      t.text :sinopsis
      t.string :audio
      t.string :calidad
      t.string :formato_video
      t.string :codigo

      t.timestamps
    end
  end
end
