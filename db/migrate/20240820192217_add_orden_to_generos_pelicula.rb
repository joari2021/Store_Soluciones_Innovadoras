class AddOrdenToGenerosPelicula < ActiveRecord::Migration[7.1]
  def change
    add_column :generos_peliculas, :orden, :integer
  end
end
