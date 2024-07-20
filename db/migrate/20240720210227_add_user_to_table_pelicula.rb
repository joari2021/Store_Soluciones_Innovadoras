class AddUserToTablePelicula < ActiveRecord::Migration[7.1]
  def change
    add_reference :peliculas, :user, null: false, foreign_key: true
  end
end
