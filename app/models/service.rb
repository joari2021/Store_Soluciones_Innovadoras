class Service < ApplicationRecord
  belongs_to :system_service, optional: true

  # Validaciones
  validates :description, presence: true
  validates :cost_price, :sale_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :value_units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end