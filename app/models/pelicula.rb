class Pelicula < ApplicationRecord
  include PgSearch::Model
  pg_search_scope :whose_name_starts_with,
                  against: {
                    name: 'A',
                    date_estreno: 'B'
                  },
                  using: {
                    tsearch: { prefix: true }
                  }
  has_one_attached :poster

  has_many :generos_peliculas, dependent: :destroy
  has_many :generos, through: :generos_peliculas

  belongs_to :user, default: -> { Current.user }
end