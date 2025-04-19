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
    tasa = TasaCambio.find_by(description: "Dolar BCV")&.valor || 0
    (valor_en_dolares * tasa).round(2)
  end
  
  def precio_sugerido_usd(precio_costo_pack, cantidad)
    precio_costo_unidad_usd = (precio_costo_pack / cantidad).round(2)
    case nivel_ganancia
    when "Baja"
      (precio_costo_unidad_usd / (1 - 0.2)).round(2)
    when "Media"
      (precio_costo_unidad_usd / (1 - 0.3)).round(2)
    when "Alta"
      (precio_costo_unidad_usd / (1 - 0.5)).round(2)
    else
      # Si no se cumple ninguna condición, puedes devolver el precio de costo o nil
      precio_costo_unidad_usd
    end
  end
end

