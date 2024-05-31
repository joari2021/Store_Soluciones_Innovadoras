class CreateGenerosSerieTvs < ActiveRecord::Migration[7.1]
  def change
    create_table :generos_serie_tvs do |t|
      t.references :serie_tv, null: false, foreign_key: true
      t.references :genero, null: false, foreign_key: true

      t.timestamps
    end
  end
end
