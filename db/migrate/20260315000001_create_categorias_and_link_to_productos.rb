class CreateCategoriasAndLinkToProductos < ActiveRecord::Migration[7.1]
  class MigrationBusiness < ApplicationRecord
    self.table_name = 'businesses'
  end

  class MigrationProducto < ApplicationRecord
    self.table_name = 'productos'
  end

  class MigrationCategoria < ApplicationRecord
    self.table_name = 'categorias'
  end

  def up
    create_table :categorias do |t|
      t.references :business, null: false, foreign_key: true
      t.string :nombre, null: false

      t.timestamps
    end

    add_index :categorias, %i[business_id nombre], unique: true

    add_reference :productos, :categoria, null: true, foreign_key: { to_table: :categorias }

    say_with_time 'Asignando categoria Papeleria a productos existentes' do
      MigrationProducto.reset_column_information
      MigrationCategoria.reset_column_information

      MigrationBusiness.find_each do |business|
        existing_product_ids = MigrationProducto.where(business_id: business.id).pluck(:id)
        next if existing_product_ids.empty?

        categoria = MigrationCategoria.find_or_create_by!(business_id: business.id, nombre: 'Papeleria')
        MigrationProducto.where(id: existing_product_ids).update_all(categoria_id: categoria.id)
      end
    end

    change_column_null :productos, :categoria_id, false
  end

  def down
    remove_reference :productos, :categoria, foreign_key: true
    drop_table :categorias
  end
end
