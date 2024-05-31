class SerieTv < ApplicationRecord
  has_many :generos_series
  has_many :generos, through: :generos_serie_tvs
end
