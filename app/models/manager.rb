class Manager < ApplicationRecord
  has_many :service_managers

  validates :name, presence: true, uniqueness: true
end

