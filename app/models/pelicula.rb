class Pelicula < ApplicationRecord
  attr_accessor :genero_ids_order
  attr_accessor :disable_association_validation
  include PgSearch::Model
  pg_search_scope :whose_name_starts_with,
                  against: {
                    name: "A",
                    others_titles: "B",
                  },
                  using: {
                    tsearch: { prefix: true },
                  }
  ORDER_BY = {
    fecha_de_estreno_descendente: "date_estreno DESC",
    fecha_de_estreno_ascendente: "date_estreno ASC",
    nombre_descendente: "name DESC",
    nombre_ascendente: "name ASC",
    puntuacion_promedio_descendente: "promedio_ranking DESC",
    puntuacion_promedio_ascendente: "promedio_ranking ASC",
  }
  has_one_attached :poster

  has_many :generos_peliculas, dependent: :destroy
  has_many :generos, through: :generos_peliculas
  has_many :video_details, dependent: :destroy
  has_many :rankings, dependent: :destroy
  accepts_nested_attributes_for :video_details, allow_destroy: true
  accepts_nested_attributes_for :rankings, allow_destroy: true

  validates :name, presence: true
  validates :duration_hours, presence: true
  validates :duration_minutes, presence: true
  validates :director, presence: true
  validates :reparto, presence: true
  validates :sinopsis, presence: true
  validates :codigo, presence: true
  validates :link_trailer, presence: true
  validates :date_estreno, presence: true
  validates :clasification, presence: true
  validates :backdrop_image, presence: true
  validate :must_have_at_least_one_asociation
  validate :must_have_at_least_one_genre, unless: :disable_association_validation
  validate :poster_attached
  
  belongs_to :user, default: -> { Current.user }

  after_save :calcular_promedio

  def calcular_promedio
    total = 0
    count = 0

    self.rankings.each do |ranking|
      next if ranking.marked_for_destruction?

      escala = ranking.plataforma_pelicula.escala
      total += (ranking.valor / escala.to_f) * 10
      count += 1
    end

    self.promedio_ranking = count == 0 ? nil : (total / count)
    save(validate: false) if promedio_ranking_changed?
  end

  def clasification_description
    case clasification
    when "AA"
      "Películas recomendada especialmente a niños y niñas de 0 a 6 años. Sin contenido que pueda ser considerado violento, sexual o inapropiado"
    when "A"
      "Apta para todo público. Película sin contenido violento, sexual, o lenguaje inapropiado."
    when "B"
      "Apta para mayores de 12 años. Película con contenido que puede ser levemente violento o con temas maduros que no son aptos para menores de esa edad sin la supervisión de un adulto."
    when "C"
      "Apta para mayores de 18 años. Películas con contenido explícito en términos de violencia, sexualidad, o temas que requieren de un criterio adulto"
    when "D"
      "Apta solo para adultos. Películas con contenido extremadamente explícito en violencia, sexualidad, lenguaje u otros temas que las hacen inapropiadas para menores de edad."
    when "E"
      "De exhibición especial dirigidas a un público específico, como cine experimental, cultural o de interés especializado, y no al público general"
    else
      "Clasificación no disponible."
    end
  end

  private

  def must_have_at_least_one_asociation
    if video_details.empty?
      errors.add(:video_details, "La película debe tener al menos un Video Details asociado.")
    end

    if rankings.reject(&:marked_for_destruction?).empty?
      errors.add(:rankings, "La película debe tener al menos un ranking asociado.")
    end
  end

  def must_have_at_least_one_genre
    if generos.empty?
      errors.add(:generos, "La película debe tener al menos un género asociado.")
    end
  end

  def poster_attached
    unless poster.attached?
      errors.add(:poster, "debe tener una imagen adjunta.")
    end
  end

  
end
