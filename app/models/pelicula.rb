class Pelicula < ApplicationRecord
  has_many :generos_peliculas
  has_many :generos, through: :generos_peliculas
end
