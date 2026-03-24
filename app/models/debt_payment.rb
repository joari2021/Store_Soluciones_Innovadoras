class DebtPayment < ApplicationRecord
  PAYMENT_METHODS = {
    'transfer' => 'Transferencia',
    'mobile' => 'Pago movil'
  }.freeze

  belongs_to :debt
  belongs_to :account

  attr_accessor :skip_account_movement, :movement_amount_override, :movement_occurred_at_override

  before_validation :sync_currency_from_account
  before_validation :sync_conversion_values
  after_create :create_account_movement

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :amount_in_debt_currency, presence: true, numericality: { greater_than: 0 }
  validates :exchange_rate_to_debt_currency, presence: true, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :payment_method_rules
  validate :reference_rules
  validate :currency_matches_account

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.to_s.humanize
  end

  def excess_payment?
    excess_amount_usd_bcv > 0.01.to_d
  end

  def excess_amount_usd_bcv
    @excess_amount_usd_bcv ||= begin
      payment_usd = payment_amount_usd_bcv(self)
      if payment_usd.positive?
        remaining_before = remaining_usd_bcv_before_payment
        available_before = [remaining_before, 0.to_d].max
        excess = payment_usd - available_before
        excess.positive? ? excess.round(2) : 0.to_d
      else
        0.to_d
      end
    end
  end

  private

  def payment_method_rules
    return if account.blank?

    if account.account_type == 'bank_account'
      errors.add(:payment_method, 'es requerido') if payment_method.blank?
    elsif payment_method.present?
      errors.add(:payment_method, 'solo aplica a cuentas bancarias')
    end
  end

  def reference_rules
    return if account.blank?
    return unless account.account_type == 'bank_account'
    return if payment_method.blank?

    if reference.blank?
      errors.add(:reference, 'es requerido')
      return
    end

    errors.add(:reference, 'debe tener 6 digitos') unless reference.to_s.match?(/\A\d{6}\z/)
  end

  def currency_matches_account
    return if account.blank?
    return if currency.blank?
    return if account.currency == currency

    errors.add(:currency, 'debe coincidir con la moneda de la cuenta')
  end

  def sync_currency_from_account
    return if account.blank?

    self.currency = account.currency
  end

  def sync_conversion_values
    return if debt.blank?
    return if currency.blank?
    return if amount.blank?

    conversion = CurrencyConverter.convert(
      amount: amount,
      from_currency: currency,
      to_currency: debt.currency,
      on_date: occurred_at
    )

    if conversion.blank?
      errors.add(:currency, "no tiene tasa de conversion disponible hacia #{debt.currency}")
      return
    end

    self.exchange_rate_to_debt_currency = conversion[:rate]
    self.amount_in_debt_currency = conversion[:amount]
  end

  def create_account_movement
    return if skip_account_movement

    override_amount = movement_amount_override.to_d
    movement_amount = override_amount.positive? ? override_amount : amount
    movement_occurred_at = movement_occurred_at_override.presence || occurred_at

    movement_attrs = {
      movement_kind: debt.receivable? ? 'income' : 'expense',
      amount: movement_amount,
      description: build_movement_description,
      occurred_at: movement_occurred_at
    }

    if account.account_type == 'bank_account' && payment_method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(payment_method)
    end

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description
    if debt.service_cost_record?
      service_cost_description = build_service_cost_movement_description
      base = "#{service_cost_description} [DEBT:#{debt.id}] [DP:#{id}]"
      return base if reference.blank?

      return "#{base} - Ref #{reference}"
    end

    action = debt.receivable? ? 'Cobro de deuda' : 'Pago de deuda'
    debt_description = excess_payment? ? 'Excedente' : (debt.description.to_s.strip.presence || 'Deuda sin descripcion')
    cliente_name = debt.counterparty_display_name
    base = "#{action}: #{cliente_name} (#{debt_description}) [DEBT:#{debt.id}] [DP:#{id}]"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
  end

  def build_service_cost_movement_description
    service_name = debt.service_cost_details_hash['service_name'].to_s.strip.presence ||
                   debt.service&.description.to_s.strip.presence ||
                   'Servicio'
    service_name = service_name_with_system_service(service_name)

    line = service_cost_line_from_notes
    return "Pago de costo por servicio #{service_name}" if line.blank?

    source_name = line['source_name'].to_s.strip.presence || 'clasificacion'

    case line['classification'].to_s
    when 'manager_expense'
      "Pago #{source_name} por servicio #{service_name}"
    when 'variable_expense'
      "Pago de #{source_name} por servicio de #{service_name}"
    else
      "Pago de costo por servicio #{service_name}"
    end
  end

  def service_name_with_system_service(base_service_name)
    service = debt.service || Service.includes(:system_service).find_by(id: debt.service_id)
    system_service_name = service&.system_service&.name.to_s.strip
    return base_service_name if system_service_name.blank?

    "#{base_service_name} (#{system_service_name})"
  end

  def service_cost_line_from_notes
    line_id = notes.to_s[/\[LINE:([^\]]+)\]/, 1].to_s.strip
    return nil if line_id.blank?

    debt.service_cost_lines.find { |line| line['line_id'].to_s == line_id }
  end

  def normalize_account_movement_method(method)
    return 'mobile_payment' if method.to_s == 'mobile'

    method.to_s
  end

  def remaining_usd_bcv_before_payment
    (debt_amount_usd_bcv - paid_usd_bcv_before_payment).round(2)
  end

  def paid_usd_bcv_before_payment
    other_payments = if debt.debt_payments.loaded?
                       debt.debt_payments.reject { |payment| payment.id == id }
                     else
                       debt.debt_payments.where.not(id: id).to_a
                     end

    current_key = payment_sort_key(self)

    other_payments.sum do |payment|
      (payment_sort_key(payment) <=> current_key) == -1 ? payment_amount_usd_bcv(payment) : 0.to_d
    end.round(2)
  end

  def debt_amount_usd_bcv
    convert_to_usd_bcv(
      amount: debt.amount.to_d,
      from_currency: debt.currency,
      on_date: debt.issued_on
    )
  end

  def payment_amount_usd_bcv(payment)
    convert_to_usd_bcv(
      amount: payment.amount.to_d,
      from_currency: payment.currency,
      on_date: payment.occurred_at
    )
  end

  def payment_sort_key(payment)
    [
      payment.occurred_at || Date.new(1970, 1, 1),
      payment.created_at || Time.zone.at(0),
      payment.id.to_i
    ]
  end

  def convert_to_usd_bcv(amount:, from_currency:, on_date:)
    conversion = CurrencyConverter.convert(
      amount: amount,
      from_currency: from_currency,
      to_currency: 'USD',
      on_date: on_date
    )

    conversion&.dig(:amount).to_d
  end
end
