class GenerosPelicula < ApplicationRecord
  belongs_to :pelicula
  belongs_to :genero

  validates :orden, presence: true
end
