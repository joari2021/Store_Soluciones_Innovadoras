class BusinessUserAssignment < ApplicationRecord
  AUTHORIZATION_LEVELS = %w[administrator manager standard_staff].freeze

  belongs_to :business
  belongs_to :user

  validates :authorization_level, presence: true, inclusion: { in: AUTHORIZATION_LEVELS }
  validates :user_id, uniqueness: { scope: :business_id }

  scope :active, -> { where(active: true) }
  scope :for_business, ->(business_id) { where(business_id: business_id) }

  def manager?
    authorization_level == 'manager'
  end

  def standard_staff?
    authorization_level == 'standard_staff'
  end
end
