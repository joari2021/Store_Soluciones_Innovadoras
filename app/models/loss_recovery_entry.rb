class LossRecoveryEntry < ApplicationRecord
  belongs_to :business
  belongs_to :venta
  belongs_to :account, optional: true

  validates :occurred_at, presence: true
  validates :real_total_base, :charged_total_base, :excess_base,
            :real_total_usd, :charged_total_usd, :excess_usd,
            numericality: { greater_than_or_equal_to: 0 }
  validates :base_currency, presence: true, inclusion: { in: %w[USD VES] }
end
