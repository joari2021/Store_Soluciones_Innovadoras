class RestructureServicePricingAndExpenses < ActiveRecord::Migration[7.1]
  class MigrationService < ApplicationRecord
    self.table_name = 'services'

    has_many :migration_service_managers,
             class_name: 'RestructureServicePricingAndExpenses::MigrationServiceManager',
             foreign_key: :service_id,
             inverse_of: :migration_service
  end

  class MigrationServiceManager < ApplicationRecord
    self.table_name = 'service_managers'

    belongs_to :migration_service,
               class_name: 'RestructureServicePricingAndExpenses::MigrationService',
               foreign_key: :service_id,
               inverse_of: :migration_service_managers
  end

  class MigrationTasaCambio < ApplicationRecord
    self.table_name = 'tasa_cambios'
  end

  class MigrationServiceExpenseStructure < ApplicationRecord
    self.table_name = 'service_expense_structures'
  end

  class MigrationServiceManagerExpense < ApplicationRecord
    self.table_name = 'service_manager_expenses'
  end

  def up
    add_column :services, :pricing_mode, :string, null: false, default: 'fixed'
    add_column :services, :nested_available, :boolean, null: false, default: false
    add_index :services, :pricing_mode
    add_index :services, :nested_available

    create_table :service_expense_structures do |t|
      t.references :service, null: false, foreign_key: true
      t.string :description, null: false
      t.timestamps
    end

    create_table :service_manager_expenses do |t|
      t.references :service_expense_structure, null: false, foreign_key: true
      t.references :manager, null: false, foreign_key: true
      t.decimal :amount_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amount_bs, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end

    create_table :service_variable_expenses do |t|
      t.references :service_expense_structure, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :amount_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amount_bs, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end

    create_table :service_nested_expenses do |t|
      t.references :service_expense_structure, null: false, foreign_key: true
      t.references :nested_service, null: false, foreign_key: { to_table: :services }
      t.decimal :quantity, precision: 12, scale: 2, null: false, default: 1
      t.timestamps
    end

    create_table :service_product_expenses do |t|
      t.references :service_expense_structure, null: false, foreign_key: true
      t.references :producto, null: false, foreign_key: true
      t.decimal :quantity, precision: 12, scale: 2, null: false, default: 1
      t.timestamps
    end

    migrate_existing_service_managers!
  end

  def down
    drop_table :service_product_expenses
    drop_table :service_nested_expenses
    drop_table :service_variable_expenses
    drop_table :service_manager_expenses
    drop_table :service_expense_structures

    remove_index :services, :nested_available
    remove_index :services, :pricing_mode
    remove_column :services, :nested_available
    remove_column :services, :pricing_mode
  end

  private

  def migrate_existing_service_managers!
    rates_by_description = load_latest_rates
    bcv_rate = rates_by_description['Dolar BCV'].to_d

    MigrationService.includes(:migration_service_managers).find_each do |service|
      next if service.migration_service_managers.empty?

      structure = MigrationServiceExpenseStructure.create!(
        service_id: service.id,
        description: 'Migrated managers and contracts'
      )

      service.migration_service_managers.each do |legacy_manager|
        next if legacy_manager.manager_id.blank?

        reference_key = legacy_manager.reference_cost.to_s
        reference_rate = rates_by_description[reference_key].to_d
        reference_rate = bcv_rate if reference_rate <= 0

        amount_bs = legacy_manager.cost.to_d * reference_rate
        amount_usd = if bcv_rate.positive?
                       (amount_bs / bcv_rate).round(2)
                     else
                       legacy_manager.cost.to_d
                     end

        MigrationServiceManagerExpense.create!(
          service_expense_structure_id: structure.id,
          manager_id: legacy_manager.manager_id,
          amount_usd: amount_usd,
          amount_bs: amount_bs.round(2)
        )
      end

      service.update_columns(cost: true)
    end
  end

  def load_latest_rates
    rates = {}

    MigrationTasaCambio
      .select('DISTINCT ON (description) description, valor')
      .order('description ASC, fecha_referencia DESC, created_at DESC')
      .each do |row|
        rates[row.description.to_s] = row.valor.to_d
      end

    rates
  end
end
