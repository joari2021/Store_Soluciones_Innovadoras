class ExpenseCategory < ApplicationRecord
  belongs_to :business
  has_many :expenses, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :business_id, case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
