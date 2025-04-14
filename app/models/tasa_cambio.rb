class TasaCambio < ApplicationRecord
  validates :description, presence: true
  validates :valor, presence: true, numericality: { greater_than: 0 }
end