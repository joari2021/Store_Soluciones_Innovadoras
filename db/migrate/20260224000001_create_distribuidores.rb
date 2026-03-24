class CreateDistribuidores < ActiveRecord::Migration[7.0]
  def change
    create_table :distribuidores do |t|
      t.string :nombre, null: false
      t.string :ruc
      t.string :telefono
      t.string :email
      t.text :direccion

      t.timestamps
    end
  end
end
