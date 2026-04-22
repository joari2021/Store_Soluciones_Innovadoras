class CashShift < ApplicationRecord
  STATUSES = {
    'open' => 'Abierto',
    'closed' => 'Cerrado'
  }.freeze

  belongs_to :business
  belongs_to :opened_by, class_name: 'User', inverse_of: :opened_cash_shifts
  belongs_to :closed_by, class_name: 'User', inverse_of: :closed_cash_shifts, optional: true
  belongs_to :active_cashier, class_name: 'User', optional: true

  has_many :ventas, dependent: :nullify
  has_many :venta_payments, through: :ventas

  scope :open, -> { where(status: 'open').order(opened_at: :desc) }
  scope :closed, -> { where(status: 'closed').order(closed_at: :desc) }

  validates :status, presence: true, inclusion: { in: STATUSES.keys }
  validates :opened_at, presence: true
  validates :opening_balance_ves, numericality: { greater_than_or_equal_to: 0 }
  validates :opening_balance_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :declared_closing_ves, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :declared_closing_usd, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :single_open_shift_per_business, if: :open?
  validate :active_cashier_is_eligible

  before_validation :set_defaults

  def open?
    status == 'open'
  end

  def closed?
    status == 'closed'
  end

  def status_label
    STATUSES[status] || status.to_s.humanize
  end

  def total_sales_usd
    ventas.where(status: 'paid').sum(:total_usd).to_d
  end

  def total_sales_ves
    ventas.where(status: 'paid').sum(:total_bs).to_d
  end

  def incoming_payments
    venta_payments.where(payment_kind: 'in')
  end

  def outgoing_payments
    venta_payments.where(payment_kind: 'out')
  end

  def close!(user:, declared_closing_ves: nil, declared_closing_usd: nil, notes: nil)
    unless active_cashier_id.present? && user.present? && active_cashier_id == user.id
      errors.add(:base, 'El turno solo puede ser cerrado por el cajero activo.')
      raise ActiveRecord::RecordInvalid, self
    end

    update!(
      status: 'closed',
      closed_at: Time.current,
      closed_by: user,
      active_cashier: nil,
      declared_closing_ves: declared_closing_ves,
      declared_closing_usd: declared_closing_usd,
      closing_notes: notes
    )
  end

  private

  def set_defaults
    self.status = 'open' if status.blank?
    self.opened_at ||= Time.current
    self.opening_balance_ves = opening_balance_ves.to_d
    self.opening_balance_usd = opening_balance_usd.to_d
  end

  def single_open_shift_per_business
    return if business_id.blank?

    conflict = self.class.where(business_id: business_id, status: 'open')
    conflict = conflict.where.not(id: id) if persisted?
    return unless conflict.exists?

    errors.add(:base, 'Ya existe un turno abierto para este negocio.')
  end

  def active_cashier_is_eligible
    return if active_cashier.blank?

    if active_cashier.business_id != business_id
      errors.add(:active_cashier, 'debe pertenecer al mismo negocio del turno.')
      return
    end

    unless active_cashier.admin? || active_cashier.manager?
      errors.add(:active_cashier, 'debe ser administrador o encargado.')
      return
    end

    return if active_cashier.active?

    errors.add(:active_cashier, 'debe estar activo para cobrar.')
  end
end
