class CasheaUserFinancing < ApplicationRecord
  LINE_MODES = %w[cotidiana principal].freeze

  belongs_to :business
  belongs_to :created_by, class_name: 'User', optional: true

  validates :user_name, presence: true
  validates :line_mode, presence: true, inclusion: { in: LINE_MODES }
  validates :initial_ficticia_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :payable_group_token, presence: true
  validates :receivable_group_token, presence: true
end
