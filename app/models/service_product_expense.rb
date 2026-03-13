class ServiceProductExpense < ApplicationRecord
  belongs_to :service_expense_structure
  belongs_to :producto

  validates :quantity, numericality: { greater_than: 0 }

  def total_usd
    (producto&.precio_venta_usd.to_d * quantity.to_d).round(2)
  end

  def total_bs(tasa_dolar: nil)
    rate = tasa_dolar.to_d
    rate = TasaCambio.latest_value('Dolar BCV').to_d unless rate.positive?
    return 0.to_d unless rate.positive?

    (total_usd * rate).round(2)
  end
end
