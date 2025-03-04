class Appointment < ApplicationRecord
  belongs_to :saime_user

  validates :appointment_type, :appointment_date, :appointment_time, :status, presence: true
  validates :reschedulable, inclusion: { in: [true, false] }
end
