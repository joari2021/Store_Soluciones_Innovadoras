class RemoveColumnToPelicula < ActiveRecord::Migration[7.1]
  def change
    remove_column :peliculas, :subtitle, :string
    remove_column :peliculas, :audio, :string
    remove_column :peliculas, :calidad_video, :string
  end
end
