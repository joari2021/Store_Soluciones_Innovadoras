class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :appointments do |t|
      t.string :appointment_type, null: false
      t.datetime :appointment_date
      t.string :appointment_time
      t.string :status, null: false, default: "activa"
      t.boolean :reschedulable, null: false, default: true
      t.references :saime_user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
