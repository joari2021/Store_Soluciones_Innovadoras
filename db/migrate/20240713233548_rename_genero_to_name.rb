class RenameGeneroToName < ActiveRecord::Migration[7.1]
  def change
    rename_column :generos, :genero, :name
  end
end
