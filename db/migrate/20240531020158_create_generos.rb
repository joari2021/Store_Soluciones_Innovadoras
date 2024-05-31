class CreateGeneros < ActiveRecord::Migration[7.1]
  def change
    create_table :generos do |t|
      t.string :genero

      t.timestamps
    end
  end
end
