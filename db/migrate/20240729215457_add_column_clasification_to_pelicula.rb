class AddColumnClasificationToPelicula < ActiveRecord::Migration[7.1]
  def change
    add_column :peliculas, :clasification, :string
  end
end
