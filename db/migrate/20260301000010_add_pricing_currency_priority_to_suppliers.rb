class AddPricingCurrencyPriorityToSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :pricing_currency_priority, :string, null: false, default: 'usd'
  end
end
