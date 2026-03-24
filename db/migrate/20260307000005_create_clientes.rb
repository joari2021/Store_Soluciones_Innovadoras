class CreateClientes < ActiveRecord::Migration[7.1]
  def change
    create_table :clientes do |t|
      t.references :business, null: false, foreign_key: true
      t.string :document_type, null: false
      t.string :document_number
      t.string :name, null: false
      t.string :phone
      t.text :address
      t.timestamps
    end

    add_index :clientes, :name
    add_index :clientes, %i[business_id document_type document_number], name: "index_clientes_on_business_doc"
  end
end
