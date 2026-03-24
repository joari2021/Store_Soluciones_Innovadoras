class CreateVentas < ActiveRecord::Migration[7.1]
  def change
    create_table :ventas do |t|
      t.references :business, null: false, foreign_key: true
      t.string :status, null: false, default: 'draft'
      t.decimal :total_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total_bs, precision: 14, scale: 2, null: false, default: 0
      t.decimal :tasa_dolar, precision: 12, scale: 4
      t.text :notes
      t.timestamps
    end

    add_index :ventas, :status
  end
end
