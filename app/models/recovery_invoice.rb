class RecoveryInvoice < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  has_many :recovery_invoice_items, dependent: :destroy

  validates :occurred_at, presence: true
  validates :total_usd, numericality: { greater_than_or_equal_to: 0 }

  def recalculate_total!
    total = recovery_invoice_items.sum('total_price_usd')
    update!(total_usd: total)
  end
end
