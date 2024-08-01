class CreateRankings < ActiveRecord::Migration[7.1]
  def change
    create_table :rankings do |t|
      t.references :pelicula, null: false, foreign_key: true
      t.references :plataforma_pelicula, null: false, foreign_key: true
      t.float :valor, null: false

      t.timestamps
    end
  end
end
