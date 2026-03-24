class AddDefaultExentoToSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :default_exento, :boolean, default: false, null: false
  end
end
