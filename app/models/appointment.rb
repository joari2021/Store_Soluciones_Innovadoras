class Appointment < ApplicationRecord
  belongs_to :saime_user

  enum appointment_type: { cedula: "cedula", civil: "civil", niño: "niño" }

  validates :appointment_type, :appointment_date, :status, presence: true
  validates :reschedulable, inclusion: { in: [true, false] }
  validate :valid_appointment_date

  def valid_appointment_date
    return if appointment_date.blank?

    min_date = Date.today
    max_date = Date.today + 3.months

    unless (min_date..max_date).cover?(appointment_date.to_date)
      errors.add(:appointment_date, "must be within the next three months")
    end
  end
end
