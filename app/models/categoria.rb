class Categoria < ApplicationRecord
  self.table_name = 'categorias'

  belongs_to :business
  has_many :productos, dependent: :restrict_with_error

  validates :nombre, presence: true, uniqueness: { scope: :business_id, case_sensitive: false }

  before_validation :normalize_nombre

  private

  def normalize_nombre
    self.nombre = nombre.to_s.strip
  end
end
