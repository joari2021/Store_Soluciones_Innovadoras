class AddReferenceFieldsToServiceNestedExpenses < ActiveRecord::Migration[7.1]
  def change
    add_column :service_nested_expenses, :currency_reference, :string, null: false, default: 'Bs'
    add_column :service_nested_expenses, :amount_reference, :decimal, precision: 14, scale: 2, null: false, default: 0
  end
end
