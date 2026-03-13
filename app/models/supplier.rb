class Supplier < ApplicationRecord
  PRICING_CURRENCY_PRIORITIES = %w[usd bs].freeze

  belongs_to :business
  has_many :supplier_products, dependent: :destroy
  has_many :productos, through: :supplier_products

  has_many :purchase_invoices, class_name: 'PurchaseInvoice', foreign_key: :supplier_id, dependent: :nullify
  has_many :debts, foreign_key: :supplier_id, dependent: :nullify

  accepts_nested_attributes_for :supplier_products, allow_destroy: true

  validates :nombre, presence: true
  validates :pricing_currency_priority, inclusion: { in: PRICING_CURRENCY_PRIORITIES }
end
