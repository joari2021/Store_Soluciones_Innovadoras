class SaimeUser < ApplicationRecord
  belongs_to :user, optional: true  # Si el usuario de la app es opcional
  has_many :appointments, dependent: :destroy

  validates :identification, presence: true, uniqueness: true
  validates :entry, presence: true
end
