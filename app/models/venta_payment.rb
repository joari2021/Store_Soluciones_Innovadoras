class VentaPayment < ApplicationRecord
  self.table_name = "venta_payments"
  METHODS = {
    "cash" => "Efectivo",
    "transfer" => "Transferencia",
    "mobile" => "Pago movil",
    "card" => "Tarjeta",
    "pos" => "Punto de venta",
    "biopago" => "Biopago",
    "cashea" => "Cashea",
    "zelle" => "Zelle",
    "wallet" => "Billetera digital",
    "crypto" => "Cripto",
  }.freeze

  PAYMENT_KINDS = {
    "in" => "Pago",
    "out" => "Vuelto",
  }.freeze

  belongs_to :venta
  belongs_to :account, optional: true

  validates :payment_method, presence: true, inclusion: { in: METHODS.keys }
  validates :amount_usd, numericality: { greater_than: 0 }, unless: :ves_currency?
  validates :amount_usd, numericality: { greater_than_or_equal_to: 0 }, if: :ves_currency?
  validates :amount_original, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :payment_kind, presence: true, inclusion: { in: PAYMENT_KINDS.keys }
  validates :reference, presence: true, format: { with: /\A\d{4}\z/, message: "debe tener 4 digitos" },
                        if: :reference_required?
  validates :payment_date, presence: true, if: :reference_required?

  before_validation :set_defaults
  before_validation :set_amount_bs

  def payment_method_label
    METHODS[payment_method] || payment_method.to_s.humanize
  end

  def payment_kind_label
    PAYMENT_KINDS[payment_kind] || payment_kind.to_s.humanize
  end

  private

  def set_defaults
    self.currency = "USD" if currency.blank?
    self.amount_original = amount_usd if amount_original.to_d <= 0
    self.payment_kind = "in" if payment_kind.blank?
  end

  def set_amount_bs
    rate = venta&.tasa_dolar.to_d
    self.amount_bs = if currency == "VES"
        amount_original.to_d
      else
        rate.positive? ? amount_usd.to_d * rate : 0
      end
  end

  def reference_required?
    %w[transfer mobile].include?(payment_method)
  end

  def ves_currency?
    currency.to_s == "VES"
  end
end
