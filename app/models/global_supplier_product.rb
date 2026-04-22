class GlobalSupplierProduct < ApplicationRecord
  belongs_to :global_supplier
  belongs_to :global_product

  has_many :supplier_products, dependent: :nullify

  validates :global_supplier_id, uniqueness: { scope: :global_product_id }
end
