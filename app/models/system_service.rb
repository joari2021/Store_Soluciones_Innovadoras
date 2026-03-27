class SystemService < ApplicationRecord
  has_many :services, dependent: :nullify
  has_one_attached :image

  # Validaciones
  validates :name, presence: true, uniqueness: true

  def recarga_system?
    normalized = I18n.transliterate(name.to_s).downcase.strip
    normalized.include?('recarga')
  end
end