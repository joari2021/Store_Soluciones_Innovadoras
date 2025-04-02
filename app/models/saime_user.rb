class SaimeUser < ApplicationRecord
  belongs_to :user, optional: true
  has_many :appointments, dependent: :destroy
  
  accepts_nested_attributes_for :appointments, allow_destroy: true, 
    reject_if: proc { |attributes| attributes['appointment_date'].blank? && attributes['appointment_type'].blank? }

  validates :identification, presence: true, uniqueness: true
  validates :entry, presence: true

  # Scope para "Citas Disponibles": Usuarios que tengan al menos una cita con fecha a partir de hoy y status "disponible".
  scope :with_available_appointments, -> {
    joins(:appointments)
      .where("appointments.appointment_date >= ? AND appointments.status = ?", Date.today, "disponible")
      .group("saime_users.id")
      .order("MIN(appointments.appointment_date) ASC")
  }

  # Scope para "Citas No Programables": Usuarios cuyos todas las citas tengan status "inprogramable".
  scope :with_non_schedulable_appointments, -> {
  joins(:appointments)
    .group("saime_users.id")
    .having("COUNT(appointments.id) > 0 AND COUNT(CASE WHEN appointments.status <> ? THEN 1 END) = 0", "inprogramable")
  }


  # Scope para "Citas Apartadas": Usuarios con al menos una cita con status "apartadas" o "pagadas", ordenados por la cita más próxima.
  scope :with_reserved_appointments, -> {
    joins(:appointments)
      .where("appointments.status IN (?)", ["apartada", "pagada"])
      .group("saime_users.id")
      .order("MIN(appointments.appointment_date) ASC")
  }

  # Scope para "Usuarios Bloqueados Temporalmente": temporary_status igual a "error en clave".
  scope :temporarily_blocked, -> { where(temporary_status: "error en clave") }

  # Scope para "Usuarios Bloqueados": confirmed_status igual a "bad request".
  scope :blocked, -> { where(confirmed_status: "bad request") }

  # Scope para "Citas por Agendar": Usuarios sin citas asociadas.
  scope :without_appointments, -> {
  left_outer_joins(:appointments)
    .group("saime_users.id")
    .having(
      "(COUNT(appointments.id) = 0 OR (SUM(CASE WHEN appointments.appointment_date >= ? THEN 1 ELSE 0 END) = 0 AND SUM(CASE WHEN appointments.appointment_date <= ? THEN 1 ELSE 0 END) > 0)) AND SUM(CASE WHEN appointments.status = 'pagada' THEN 1 ELSE 0 END) = 0",
      Date.tomorrow, Date.today
    )
  }
end
