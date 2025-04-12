class CreateServices < ActiveRecord::Migration[7.1]
  def change
    create_table :services do |t|
      t.string :description
      t.boolean :cost
      t.float :cost_price
      t.string :currency_cost_price
      t.float :value_units
      t.float :sale_price
      t.string :currency_base_price

      t.timestamps
    end
  end
end
