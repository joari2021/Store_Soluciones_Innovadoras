class Manager < ApplicationRecord
  has_many :service_managers
  has_many :service_manager_expenses, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
