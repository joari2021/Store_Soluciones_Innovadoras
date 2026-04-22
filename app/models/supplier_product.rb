class SupplierProduct < ApplicationRecord
  belongs_to :supplier
  belongs_to :producto
  belongs_to :global_supplier_product, optional: true

  validates :producto, :supplier, presence: true
end
