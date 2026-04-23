class ExpenseCategory < ApplicationRecord
  belongs_to :business
  has_many :expenses, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :business_id }
end
