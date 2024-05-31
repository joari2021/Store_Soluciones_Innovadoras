class GenerosJuego < ApplicationRecord
  belongs_to :juego
  belongs_to :genero
end
