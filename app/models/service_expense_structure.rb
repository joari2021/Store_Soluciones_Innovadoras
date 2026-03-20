class ServiceExpenseStructure < ApplicationRecord
  belongs_to :service

  scope :enabled_for_sales, -> { where(active_for_sales: true) }

  has_many :service_manager_expenses, dependent: :destroy
  has_many :service_variable_expenses, dependent: :destroy
  has_many :service_nested_expenses, dependent: :destroy
  has_many :service_product_expenses, dependent: :destroy

  accepts_nested_attributes_for :service_manager_expenses, allow_destroy: true
  accepts_nested_attributes_for :service_variable_expenses, allow_destroy: true
  accepts_nested_attributes_for :service_nested_expenses, allow_destroy: true
  accepts_nested_attributes_for :service_product_expenses, allow_destroy: true

  validates :description, presence: true

  def total_usd(tasa_dolar: nil, unidad_vi: nil)
    manager_total = service_manager_expenses.sum { |row| row.current_amount_usd(tasa_dolar: tasa_dolar) }
    variable_total = service_variable_expenses.sum { |row| row.current_amount_usd(tasa_dolar: tasa_dolar) }
    nested_total = service_nested_expenses.sum { |row| row.total_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi) }
    product_total = service_product_expenses.sum { |row| row.total_usd }

    (manager_total + variable_total + nested_total + product_total).round(2)
  end

  def total_bs(tasa_dolar: nil, unidad_vi: nil)
    rate = tasa_dolar.to_d
    rate = TasaCambio.latest_value("Dolar BCV").to_d unless rate.positive?

    manager_total = service_manager_expenses.sum { |row| row.current_amount_bs }
    variable_total = service_variable_expenses.sum { |row| row.current_amount_bs }
    nested_total = service_nested_expenses.sum { |row| row.total_bs(tasa_dolar: rate, unidad_vi: unidad_vi) }
    product_total = service_product_expenses.sum { |row| row.total_bs(tasa_dolar: rate) }

    (manager_total + variable_total + nested_total + product_total).round(2)
  end
end
