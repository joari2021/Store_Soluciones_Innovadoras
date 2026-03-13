class Venta < ApplicationRecord
  self.table_name = 'ventas'
  VAT_MODES = {
    'none' => 'Sin IVA',
    'add' => 'Agregar IVA',
    'included' => 'Invertido'
  }.freeze

  BASE_CURRENCIES = {
    'USD' => 'Dolares',
    'VES' => 'Bolivares'
  }.freeze

  STATUSES = {
    'draft' => 'Borrador',
    'paid' => 'Pagada',
    'void' => 'Anulada'
  }.freeze

  belongs_to :business
  belongs_to :cliente, optional: true
  has_many :venta_items, dependent: :destroy, inverse_of: :venta
  has_many :venta_payments, dependent: :destroy, inverse_of: :venta

  accepts_nested_attributes_for :venta_items, allow_destroy: true
  accepts_nested_attributes_for :venta_payments, allow_destroy: true

  validates :status, presence: true, inclusion: { in: STATUSES.keys }
  validates :vat_mode, presence: true, inclusion: { in: VAT_MODES.keys }
  validates :vat_rate, numericality: { greater_than_or_equal_to: 0 }
  validates :base_currency, presence: true, inclusion: { in: BASE_CURRENCIES.keys }

  before_validation :apply_vat_defaults
  before_validation :calculate_totals

  def status_label
    STATUSES[status] || status.to_s.humanize
  end

  def vat_mode_label
    VAT_MODES[vat_mode] || vat_mode.to_s.humanize
  end

  def cliente_display_name
    cliente&.name.presence || 'Cliente general'
  end

  def base_currency_ves?
    base_currency == 'VES'
  end

  def base_rate
    tasa_dolar.to_d
  end

  def base_unit_price(item)
    unit_usd = item.unit_price_usd.to_d
    return unit_usd unless base_currency_ves?

    rate = base_rate
    return 0.to_d unless rate.positive?

    if vat_mode == 'included'
      gross_usd = (unit_usd * (1 + vat_rate.to_d)).round(4)
      gross_base = (gross_usd * rate).round(2)
      (gross_base / (1 + vat_rate.to_d)).round(2)
    else
      (unit_usd * rate).round(2)
    end
  end

  def base_line_subtotal(item)
    return item.subtotal_usd.to_d.round(2) unless base_currency_ves?

    (base_unit_price(item) * item.quantity.to_d).round(2)
  end

  def base_subtotal
    return subtotal_usd.to_d.round(2) unless base_currency_ves?

    venta_items.reject(&:marked_for_destruction?).sum { |item| base_line_subtotal(item) }.round(2)
  end

  def base_vat
    return vat_usd.to_d.round(2) unless base_currency_ves?
    return 0.to_d if vat_mode == 'none'

    (base_subtotal * vat_rate.to_d).round(2)
  end

  def base_total
    return total_usd.to_d.round(2) unless base_currency_ves?

    (base_subtotal + base_vat).round(2)
  end

  private

  def apply_vat_defaults
    self.vat_mode = 'none' if vat_mode.blank?
    self.vat_rate = 0.16 if vat_rate.blank?
    self.base_currency = 'USD' if base_currency.blank?
  end

  def calculate_totals
    active_items = venta_items.reject(&:marked_for_destruction?)
    subtotal = active_items.sum { |item| item.subtotal_usd.to_d }
    rate = vat_rate.to_d
    vat_value = vat_mode == 'none' ? 0.to_d : subtotal * rate

    self.subtotal_usd = subtotal.round(2)
    self.vat_usd = vat_value.round(2)
    self.total_usd = (subtotal + vat_value).round(2)

    exchange_rate = tasa_dolar.to_d
    self.total_bs = if base_currency_ves?
                      exchange_rate.positive? ? base_total : 0
                    else
                      exchange_rate.positive? ? (total_usd * exchange_rate).round(2) : 0
                    end
  end
end
