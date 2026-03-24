class SupplierProduct < ApplicationRecord
  belongs_to :supplier
  belongs_to :producto

  validates :producto, :supplier, presence: true
end
