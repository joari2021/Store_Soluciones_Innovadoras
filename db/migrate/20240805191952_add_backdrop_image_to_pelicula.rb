class AddBackdropImageToPelicula < ActiveRecord::Migration[7.1]
  def change
    add_column :peliculas, :backdrop_image, :string
  end
end
