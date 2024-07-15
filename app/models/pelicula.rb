class Pelicula < ApplicationRecord
  has_one_attached :poster

  has_many :generos_peliculas, dependent: :destroy
  has_many :generos, through: :generos_peliculas
end