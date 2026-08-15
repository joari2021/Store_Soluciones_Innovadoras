class InventoryAbsorptionSimulation < ApplicationRecord
  MODES = %w[move copy].freeze

  belongs_to :destination_business, class_name: 'Business'
  belongs_to :source_business, class_name: 'Business'
  belongs_to :user, optional: true

  validates :mode, presence: true, inclusion: { in: MODES }
  validates :summary, presence: true
  validates :preview, presence: true
  validates :simulated_at, presence: true
end
