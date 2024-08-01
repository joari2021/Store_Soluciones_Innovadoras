class PlataformaPelicula < ApplicationRecord
  has_many :rankings
  validates :name, presence: true, uniqueness: true
  validates :escala, presence: true
end
