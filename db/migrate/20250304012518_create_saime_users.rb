class CreateSaimeUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :saime_users do |t|
      t.integer :identification
      t.string :entry
      t.string :temporary_status, null: false, default: "activo"
      t.string :confirmed_status, null: false, default: "activo"
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end
