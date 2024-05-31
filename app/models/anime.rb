class Anime < ApplicationRecord
  has_many :generos_animes
  has_many :generos, through: :generos_animes
end
