class Service < ApplicationRecord
  include PgSearch::Model
  belongs_to :system_service, optional: true
  has_many :service_managers, dependent: :destroy
  accepts_nested_attributes_for :service_managers, allow_destroy: true
 
  # Validaciones
  validates :description, presence: true
  validates :sale_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :value_units, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  pg_search_scope :whose_name_starts_with,
                  against: { description: 'B' }, # Asigna grado "B" a la descripción del servicio
                  associated_against: {
                    system_service: { name: 'A' } # Asigna grado "A" al nombre del sistema asociado
                  },
                  using: {
                    tsearch: { prefix: true }
                  }
end



  