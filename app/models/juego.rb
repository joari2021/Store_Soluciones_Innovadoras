class Juego < ApplicationRecord
  has_many :generos_juegos
  has_many :generos, through: :generos_juegos
end
