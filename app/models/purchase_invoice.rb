class PurchaseInvoice < ApplicationRecord
  self.table_name = 'facturas'

  belongs_to :business
  belongs_to :supplier, optional: true
  has_many :purchase_invoice_items, lambda {
    order(created_at: :asc, id: :asc)
  }, class_name: 'PurchaseInvoiceItem', foreign_key: :factura_id, dependent: :destroy, inverse_of: :purchase_invoice
  has_many :productos, through: :purchase_invoice_items

  accepts_nested_attributes_for :purchase_invoice_items, allow_destroy: true

  validates :supplier, presence: true, on: :create

  before_validation :set_supplier_name_snapshot
  before_save :calcular_monto_total

  def supplier_display_name
    supplier_name.presence || supplier&.nombre || 'Proveedor'
  end

  def total_bs
    totals_breakdown[:total_bs].round(4)
  end

  def calcular_monto_total
    totals = totals_breakdown

    priority = supplier&.pricing_currency_priority.presence || 'usd'
    rate = tasa_dolar.to_d
    total_usd = if priority == 'bs'
                  rate.positive? ? (totals[:total_bs] / rate) : totals[:total_usd]
                else
                  totals[:total_usd]
                end

    self.monto_total = total_usd.round(4)
  end

  def set_supplier_name_snapshot
    self.supplier_name = supplier&.nombre if supplier_name.blank? && supplier.present?
  end

  def totals_breakdown
    active_items = purchase_invoice_items.reject(&:marked_for_destruction?)

    subtotal_usd = 0.to_d
    subtotal_bs = 0.to_d
    exento_usd = 0.to_d
    exento_bs = 0.to_d

    active_items.each do |item|
      line_usd = item.subtotal.to_d
      line_bs = item.costo_mayor_bs.to_d * item.cantidad.to_d

      if item.exento?
        exento_usd += line_usd
        exento_bs += line_bs
      else
        subtotal_usd += line_usd
        subtotal_bs += line_bs
      end
    end

    iva_usd = subtotal_usd * 0.16
    iva_bs = subtotal_bs * 0.16
    total_usd = subtotal_usd + iva_usd + exento_usd
    total_bs = subtotal_bs + iva_bs + exento_bs

    {
      subtotal_usd: subtotal_usd,
      subtotal_bs: subtotal_bs,
      exento_usd: exento_usd,
      exento_bs: exento_bs,
      iva_usd: iva_usd,
      iva_bs: iva_bs,
      total_usd: total_usd,
      total_bs: total_bs
    }
  end
end
