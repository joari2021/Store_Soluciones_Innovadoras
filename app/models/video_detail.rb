class VideoDetail < ApplicationRecord
  belongs_to :pelicula

  # Validaciones opcionales
  validates :calidad, :audio, :peso, :formato, :resolucion, :subtitulos, presence: true
end
