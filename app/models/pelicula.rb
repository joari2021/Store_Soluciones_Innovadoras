class Pelicula < ApplicationRecord
  include PgSearch::Model
  pg_search_scope :whose_name_starts_with,
                  against: {
                    name: "A",
                    date_estreno: "B",
                  },
                  using: {
                    tsearch: { prefix: true },
                  }
  ORDER_BY = {
    fecha_de_estreno_descendente: "date_estreno DESC",
    fecha_de_estreno_ascendente: "date_estreno ASC",
    nombre_descendente: "name DESC",
    nombre_ascendente: "name ASC",
  }
  has_one_attached :poster

  has_many :generos_peliculas, dependent: :destroy
  has_many :generos, through: :generos_peliculas
  has_many :rankings, dependent: :destroy
  accepts_nested_attributes_for :rankings, allow_destroy: true

  belongs_to :user, default: -> { Current.user }

  before_save :calcular_promedio
  after_update :calcular_promedio

  def calcular_promedio
    total = 0
    count = 0

    self.rankings.each do |ranking|
      escala = ranking.plataforma_pelicula.escala
      total += (ranking.valor / escala.to_f) * 10
      count += 1
    end

    self.promedio_ranking = total / count unless count == 0
  end
end
