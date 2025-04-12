class CreateSystemServices < ActiveRecord::Migration[7.1]
  def change
    create_table :system_services do |t|
      t.string :name

      t.timestamps
    end

    # Añadir la referencia de system_service a la tabla services
    add_reference :services, :system_service, foreign_key: true, null: true
  end
end
