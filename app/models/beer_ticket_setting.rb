class BeerTicketSetting < ApplicationRecord
  belongs_to :business

  has_many :beer_ticket_setting_products, dependent: :destroy
  has_many :productos, through: :beer_ticket_setting_products, source: :producto

  validates :next_serial, numericality: { only_integer: true, greater_than: 0 }

  before_validation :ensure_next_serial

  def formatted_next_serial
    format('%04d', next_serial.to_i)
  end

  private

  def ensure_next_serial
    self.next_serial = 1 if next_serial.to_i <= 0
  end
end
