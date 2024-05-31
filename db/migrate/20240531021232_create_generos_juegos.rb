class CreateGenerosJuegos < ActiveRecord::Migration[7.1]
  def change
    create_table :generos_juegos do |t|
      t.references :juego, null: false, foreign_key: true
      t.references :genero, null: false, foreign_key: true

      t.timestamps
    end
  end
end
