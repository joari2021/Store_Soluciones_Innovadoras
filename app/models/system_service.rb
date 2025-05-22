class SystemService < ApplicationRecord
  has_many :services, dependent: :nullify
  has_one_attached :image

  # Validaciones
  validates :name, presence: true, uniqueness: true
end