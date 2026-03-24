class Producto < ApplicationRecord
  include PgSearch::Model
  has_one_attached :foto

  def self.availability_column
    return 'available' if column_names.include?('available')
    return 'disponible' if column_names.include?('disponible')

    nil
  end

  def self.availability_true_sql
    column = availability_column
    return 'TRUE' if column.blank?

    "#{table_name}.#{column} = TRUE"
  end

  def available?
    if has_attribute?(:available)
      self[:available]
    elsif has_attribute?(:disponible)
      self[:disponible]
    else
      true
    end
  end

  def available=(value)
    boolean_value = ActiveModel::Type::Boolean.new.cast(value)

    if has_attribute?(:available)
      self[:available] = boolean_value
    elsif has_attribute?(:disponible)
      self[:disponible] = boolean_value
    end
  end

  def disponible?
    available?
  end

  def disponible=(value)
    self.available = value
  end

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
  
  def precio_sugerido_usd(precio_costo_unidad_usd)
    case nivel_ganancia
    when "Baja"
      precio_costo_unidad_usd / (1 - 0.15)
    when "Justa"
      precio_costo_unidad_usd / (1 - 0.23)
    when "Media"
      precio_costo_unidad_usd / (1 - 0.3)
    when "Alta"
      precio_costo_unidad_usd / (1 - 0.5)
    else
      # Si no se cumple ninguna condición, puedes devolver el precio de costo o nil
      precio_costo_unidad_usd
    end
  end
end

