class SaimeUser < ApplicationRecord
  belongs_to :user, optional: true
  has_many :appointments, dependent: :destroy
  
  accepts_nested_attributes_for :appointments, allow_destroy: true, 
    reject_if: proc { |attributes| attributes['appointment_date'].blank? && attributes['appointment_type'].blank? }

  validates :identification, presence: true, uniqueness: true
  validates :entry, presence: true
end

