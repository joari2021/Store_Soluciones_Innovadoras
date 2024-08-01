class AddPromedioRankingToPeliculas < ActiveRecord::Migration[7.1]
  def change
    add_column :peliculas, :promedio_ranking, :float
  end
end
