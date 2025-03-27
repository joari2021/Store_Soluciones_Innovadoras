class SaimeUser < ApplicationRecord
  belongs_to :user, optional: true  # Si el usuario de la app es opcional
  has_many :appointments, dependent: :destroy
  accepts_nested_attributes_for :appointments, allow_destroy: true, reject_if: :all_blank

  validates :identification, presence: true, uniqueness: true
  validates :entry, presence: true
end
