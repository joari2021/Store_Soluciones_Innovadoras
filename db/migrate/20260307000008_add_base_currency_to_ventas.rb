class AddBaseCurrencyToVentas < ActiveRecord::Migration[7.1]
  def change
    add_column :ventas, :base_currency, :string, null: false, default: 'USD'
    add_index :ventas, :base_currency
  end
end
