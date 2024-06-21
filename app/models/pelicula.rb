class Pelicula < ApplicationRecord
  has_one_attached :poster

  has_many :generos_peliculas
  has_many :generos, through: :generos_peliculas
end
