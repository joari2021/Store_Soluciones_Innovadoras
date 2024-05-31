class AddDisponibleAndLinkTrailerToPeliculas < ActiveRecord::Migration[7.1]
  def change
    add_column :peliculas, :disponible, :boolean, default: true
    add_column :peliculas, :link_trailer, :string

    add_column :serie_tvs, :disponible, :boolean, default: true
    add_column :serie_tvs, :link_trailer, :string

    add_column :animes, :disponible, :boolean, default: true
    add_column :animes, :link_trailer, :string

    add_column :juegos, :disponible, :boolean, default: true
    add_column :juegos, :link_trailer, :string
  end
end
