class Genero < ApplicationRecord
  has_many :generos_peliculas
  has_many :peliculas, through: :generos_peliculas

  has_many :generos_serie_tvs
  has_many :series, through: :generos_serie_tvs

  has_many :generos_animes
  has_many :animes, through: :generos_animes

  has_many :generos_juegos
  has_many :juegos, through: :generos_juegos

  validates :name, presence: true, uniqueness: true
end
