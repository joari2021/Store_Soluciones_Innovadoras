class BusinessUserAssignment < ApplicationRecord
  AUTHORIZATION_LEVELS = %w[manager standard_staff none].freeze
  CUSTOMER_ACCESS_LEVELS = %w[none customer customer_vip].freeze

  belongs_to :business
  belongs_to :user

  before_validation :apply_defaults

  validates :authorization_level, presence: true, inclusion: { in: AUTHORIZATION_LEVELS }
  validates :customer_access_level, presence: true, inclusion: { in: CUSTOMER_ACCESS_LEVELS }
  validates :user_id, uniqueness: { scope: :business_id }

  scope :active, -> { where(active: true) }
  scope :for_business, ->(business_id) { where(business_id: business_id) }

  def manager?
    authorization_level == 'manager'
  end

  def standard_staff?
    authorization_level == 'standard_staff'
  end

  def no_role?
    authorization_level == 'none'
  end

  def customer?
    customer_access_level == 'customer'
  end

  def customer_vip?
    customer_access_level == 'customer_vip'
  end

  def customer_access?
    customer? || customer_vip?
  end

  private

  def apply_defaults
    self.customer_access_level = 'none' if customer_access_level.blank?
    self.authorization_level = 'standard_staff' if authorization_level.blank?
    self.authorization_level = 'manager' if authorization_level == 'administrator'
  end
end
