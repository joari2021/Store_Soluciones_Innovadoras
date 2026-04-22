class GlobalSupplier < ApplicationRecord
  PRICING_CURRENCY_PRIORITIES = %w[usd bs].freeze

  has_many :global_supplier_products, dependent: :restrict_with_error
  has_many :global_products, through: :global_supplier_products

  has_many :suppliers, dependent: :nullify

  accepts_nested_attributes_for :global_supplier_products, allow_destroy: true

  belongs_to :source_business, class_name: "Business", optional: true

  validates :name, presence: true
  validates :pricing_currency_priority, inclusion: { in: PRICING_CURRENCY_PRIORITIES }
end
