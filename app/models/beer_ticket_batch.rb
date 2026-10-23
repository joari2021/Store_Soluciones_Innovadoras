class BeerTicketBatch < ApplicationRecord
  belongs_to :beer_ticket_setting_product

  delegate :producto, :beer_ticket_setting, to: :beer_ticket_setting_product

  validates :start_serial, :end_serial, :ticket_count, presence: true
  validates :start_serial, :end_serial, :ticket_count, numericality: { only_integer: true, greater_than: 0 }
  validate :end_serial_cannot_be_less_than_start

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def formatted_start_serial
    format('%04d', start_serial.to_i)
  end

  def formatted_end_serial
    format('%04d', end_serial.to_i)
  end

  private

  def end_serial_cannot_be_less_than_start
    return if end_serial.to_i >= start_serial.to_i

    errors.add(:end_serial, 'debe ser mayor o igual al serial inicial disponible.')
  end
end
