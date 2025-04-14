class CreateServiceManagers < ActiveRecord::Migration[7.1]
  def change
    create_table :service_managers do |t|
      t.references :service, null: false, foreign_key: true
      t.references :manager, null: false, foreign_key: true
      t.float :price

      t.timestamps
    end
  end
end
