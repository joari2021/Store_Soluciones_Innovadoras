class RequestedProduct < ApplicationRecord
  belongs_to :business

  before_validation :normalize_name

  validates :name, presence: true, length: { maximum: 120 },
                   uniqueness: { scope: :business_id, case_sensitive: false }
  validates :requests_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  scope :ordered_by_name, -> { order(Arel.sql('LOWER(name) ASC')) }

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/\s+/, ' ')
  end
end
