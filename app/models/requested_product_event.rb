class RequestedProductEvent < ApplicationRecord
  EVENT_KINDS = %w[created incremented].freeze

  belongs_to :business
  belongs_to :requested_product
  belongs_to :user, optional: true

  validates :event_kind, presence: true, inclusion: { in: EVENT_KINDS }
  validates :user_name, presence: true, length: { maximum: 120 }
  validates :requests_count_after, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
end
