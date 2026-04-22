class GlobalProduct < ApplicationRecord
  has_many :global_supplier_products, dependent: :restrict_with_error
  has_many :global_suppliers, through: :global_supplier_products

  has_many :productos, dependent: :nullify

  belongs_to :source_business, class_name: "Business", optional: true

  validates :name, presence: true
  validates :presentation, presence: true
  validates :cant_presentation, numericality: { only_integer: true, greater_than: 0 }
end
