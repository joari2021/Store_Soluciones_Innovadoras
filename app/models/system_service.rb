class SystemService < ApplicationRecord
  has_many :services, dependent: :nullify

  # Validaciones
  validates :name, presence: true, uniqueness: true
end