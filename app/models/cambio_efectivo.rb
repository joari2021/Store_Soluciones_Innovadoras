class CambioEfectivo < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :cash_shift, optional: true
  has_many :account_movements, dependent: :nullify

  PAYMENT_GROUPS = {
    'bank' => 'Pago movil/Transferencia',
    'pos_biopago' => 'Biopago/Punto de venta'
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

  private

  def set_defaults
    self.currency = 'VES' if currency.blank?
    self.occurred_at ||= Time.current
  end
end
