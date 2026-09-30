class CreateRequestedProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :requested_products do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :requests_count, null: false, default: 1

      t.timestamps
    end

    add_index :requested_products, %i[business_id name], unique: true
    add_index :requested_products, :requests_count
  end
end
