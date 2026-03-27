class CreateProductUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :product_usages do |t|
      t.references :business, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.references :product_variation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.decimal :quantity, precision: 14, scale: 2, null: false
      t.date :used_on, null: false
      t.text :notes

      t.timestamps
    end

    add_index :product_usages, %i[business_id used_on]
    add_index :product_usages, %i[producto_id product_variation_id]
  end
end
