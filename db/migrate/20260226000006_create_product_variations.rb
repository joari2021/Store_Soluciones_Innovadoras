class CreateProductVariations < ActiveRecord::Migration[7.0]
  def change
    create_table :product_variations do |t|
      t.references :producto, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 4, null: false, default: 0

      t.timestamps
    end
  end
end
