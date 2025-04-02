class AddAppointmentRegistrationToSaimeUser < ActiveRecord::Migration[7.1]
  def change
    add_column :saime_users, :appointment_registration, :boolean, default: false, null: false
  end
end
