class HiddenDebtGroup < ApplicationRecord
  belongs_to :business

  validates :group_key, presence: true
  validates :group_key, uniqueness: { scope: :business_id }
end
