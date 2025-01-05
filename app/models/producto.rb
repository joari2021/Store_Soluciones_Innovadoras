class Producto < ApplicationRecord
  include PgSearch::Model
  has_one_attached :foto

  pg_search_scope :whose_name_starts_with,
                  against: {
                    descripcion: "A"
                  },
                  using: {
                    tsearch: { prefix: true },
                  }

  # Calcular el precio en bolívares
  
  def calcular_precio_bs(valor_en_dolares)
    tasa = TasaCambio.last&.valor || 0
    (valor_en_dolares * tasa).round(2)
  end
  
end

