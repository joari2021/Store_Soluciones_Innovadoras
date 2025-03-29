class AddColumnClientToAppointment < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :client, :string
    change_column_default :appointments, :status, from: "activa", to: "disponible"
  end
end
