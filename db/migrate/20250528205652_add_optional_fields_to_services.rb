class AddOptionalFieldsToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :physical_requirements, :string
    add_column :services, :digital_requirements, :string
    add_column :services, :required_data, :string
    add_column :services, :personal_steps, :text
    add_column :services, :note, :text
    add_column :services, :delivery_content, :string
    add_column :services, :delivery_time, :string
    remove_column :service_managers, :symbol_tasa, :string
  end
end
