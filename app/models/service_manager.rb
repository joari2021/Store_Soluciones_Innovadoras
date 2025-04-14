class ServiceManager < ApplicationRecord
  belongs_to :service
  belongs_to :manager

  validates :cost, numericality: { greater_than_or_equal_to: 0 }
end
