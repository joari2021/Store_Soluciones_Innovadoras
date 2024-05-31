class CreateGenerosAnimes < ActiveRecord::Migration[7.1]
  def change
    create_table :generos_animes do |t|
      t.references :anime, null: false, foreign_key: true
      t.references :genero, null: false, foreign_key: true

      t.timestamps
    end
  end
end
