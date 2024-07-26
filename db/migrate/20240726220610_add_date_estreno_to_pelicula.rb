class AddDateEstrenoToPelicula < ActiveRecord::Migration[7.1]
  def change
    remove_column :peliculas, :year, :integer
    add_column :peliculas, :date_estreno, :date
  end
end
