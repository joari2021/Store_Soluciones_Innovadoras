class AddCurrencyReferenceToServiceExpenses < ActiveRecord::Migration[7.1]
  class MigrationServiceManagerExpense < ApplicationRecord
    self.table_name = 'service_manager_expenses'
  end

  class MigrationServiceVariableExpense < ApplicationRecord
    self.table_name = 'service_variable_expenses'
  end

  class MigrationService < ApplicationRecord
    self.table_name = 'services'
  end

  def up
    add_column :service_manager_expenses, :currency_reference, :string, null: false, default: 'Dolar BCV'
    add_column :service_manager_expenses, :amount_reference, :decimal, precision: 14, scale: 2, null: false, default: 0

    add_column :service_variable_expenses, :currency_reference, :string, null: false, default: 'Dolar BCV'
    add_column :service_variable_expenses, :amount_reference, :decimal, precision: 14, scale: 2, null: false, default: 0

    MigrationServiceManagerExpense.update_all(currency_reference: 'Dolar BCV',
                                              amount_reference: Arel.sql('COALESCE(amount_usd, 0)'))
    MigrationServiceVariableExpense.update_all(currency_reference: 'Dolar BCV',
                                               amount_reference: Arel.sql('COALESCE(amount_usd, 0)'))

    MigrationService.where(currency_base_price: '$').update_all(currency_base_price: 'Dolar BCV')

    MigrationService
      .where(currency_base_price: 'Bs')
      .where('COALESCE(value_units, 0) > 0')
      .update_all(currency_base_price: 'Unidad VI', sale_price: Arel.sql('COALESCE(sale_price, value_units)'))
  end

  def down
    MigrationService.where(currency_base_price: 'Dolar BCV').update_all(currency_base_price: '$')

    MigrationService
      .where(currency_base_price: 'Unidad VI')
      .where('COALESCE(value_units, 0) > 0')
      .update_all(currency_base_price: 'Bs', value_units: Arel.sql('COALESCE(sale_price, value_units)'))

    remove_column :service_variable_expenses, :amount_reference
    remove_column :service_variable_expenses, :currency_reference

    remove_column :service_manager_expenses, :amount_reference
    remove_column :service_manager_expenses, :currency_reference
  end
end
