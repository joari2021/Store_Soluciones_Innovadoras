class CambioEfectivo < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :cash_shift, optional: true
  has_many :account_movements, dependent: :nullify

  PAYMENT_GROUPS = {
    'bank' => 'Pago movil/Transferencia',
    'pos_biopago' => 'Biopago/Punto de venta',
    'cash' => 'Efectivo'
  }.freeze

  DELIVERY_OPTIONS = {
    'cash' => 'Efectivo',
    'mobile_other_banks' => 'Pago movil/transf. otros bcos',
    'third_party_bancamiga' => 'Transferencia de tercero (Bancamiga)'
  }.freeze

  validates :efectivo_vendido, presence: true, numericality: { greater_than: 0 }
  validates :monto_caja_operativa, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :monto_caja_deposito, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :monto_recibido, presence: true, numericality: { greater_than: 0 }
  validates :recargo_percent, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :payment_group, presence: true, inclusion: { in: PAYMENT_GROUPS.keys }
  validates :currency, presence: true
  validates :occurred_at, presence: true

  before_validation :set_defaults

  def payment_group_label
    PAYMENT_GROUPS[payment_group] || payment_group.to_s.humanize
  end

  def seller_display_name
    user&.display_name.presence || 'Sin usuario'
  end

  def delivery_target
    details = payment_details.is_a?(Hash) ? payment_details : {}
    value = details['delivery_target'] || details[:delivery_target]
    value.to_s == 'digital' ? 'digital' : 'cash'
  end

  def delivery_option
    details = payment_details.is_a?(Hash) ? payment_details : {}
    value = details['delivery_option'] || details[:delivery_option]
    return 'cash' if value.to_s == 'cash'
    return 'mobile_other_banks' if value.to_s == 'mobile_other_banks'
    return 'third_party_bancamiga' if value.to_s == 'third_party_bancamiga'

    delivery_target == 'digital' ? 'mobile_other_banks' : 'cash'
  end

  def delivery_option_label
    DELIVERY_OPTIONS[delivery_option] || delivery_option.to_s.humanize
  end

  def delivery_target_label
    delivery_option_label
  end

  private

  def set_defaults
    self.currency = 'VES' if currency.blank?
    self.occurred_at ||= Time.current
  end
end
