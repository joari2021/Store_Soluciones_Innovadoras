class AddColumnSubtitleToPelicula < ActiveRecord::Migration[7.1]
  def change
    add_column :peliculas, :subtitle, :string
    remove_column :peliculas, :formato_video, :string
    rename_column :peliculas, :calidad, :calidad_video
  end
end
