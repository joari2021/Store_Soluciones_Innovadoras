class AccountSettlement < ApplicationRecord
  belongs_to :account
  belongs_to :settlement_account, class_name: 'Account', optional: true
  has_many :account_movements, dependent: :nullify

  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :movements_count, numericality: { greater_than_or_equal_to: 0 }
  validates :closed_at, presence: true
  validates :credited_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :commission_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def processed?
    processed_at.present?
  end
end
