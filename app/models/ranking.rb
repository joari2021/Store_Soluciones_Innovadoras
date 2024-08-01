class Ranking < ApplicationRecord
  belongs_to :pelicula
  belongs_to :plataforma_pelicula

  validates :valor, presence: true
end
