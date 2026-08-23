class LossRecoverySetting < ApplicationRecord
  belongs_to :business

  validates :surcharge_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :min_invoice_total_usd, numericality: { greater_than_or_equal_to: 0 }

  before_validation :apply_defaults

  private

  def apply_defaults
    self.surcharge_percent = 0 if surcharge_percent.nil?
    self.min_invoice_total_usd = 5 if min_invoice_total_usd.nil?
    self.active = false if active.nil?
  end
end
