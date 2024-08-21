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
  validates :disponible, presence: true
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
      "Película recomendada especialmente para niños e infantil."
    when "A"
      "Película recomendada para todo público y edad."
    when "B"
      "Película recomendada para mayores de 10 años."
    when "C"
      "Película recomendada para mayores de 14 años."
    when "D"
      "Película recomendada para mayores de 18 años."
    when "E"
      "Película exclusivamente para adultos a partir de 21 años."
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
