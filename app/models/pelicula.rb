class Pelicula < ApplicationRecord
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
end
