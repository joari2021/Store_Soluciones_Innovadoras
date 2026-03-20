class Service < ApplicationRecord
  include PgSearch::Model

  BOLIVAR_REFERENCE = 'Bs'.freeze
  LEGACY_USD_REFERENCE = '$'.freeze
  DEFAULT_REFERENCE = 'Dolar BCV'.freeze

  belongs_to :business
  belongs_to :system_service, optional: true
  has_many :service_managers, dependent: :destroy
  has_many :service_expense_structures, dependent: :destroy
  has_many :service_cost_debts, class_name: 'Debt', dependent: :nullify

  accepts_nested_attributes_for :service_managers, allow_destroy: true
  accepts_nested_attributes_for :service_expense_structures, allow_destroy: true

  enum :pricing_mode, { fixed: 'fixed', to_agree: 'to_agree' }, default: :fixed, validate: true

  validates :description, presence: true
  validates :sale_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :value_units, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :normalize_masked_sale_price
  before_validation :normalize_currency_base_price
  before_validation :migrate_legacy_value_units_to_sale_price

  validate :validate_fixed_price_fields
  validate :validate_visibility_flags
  validate :validate_auto_cost_stock_discount_settings

  pg_search_scope :whose_name_starts_with,
                  against: { description: 'B' }, # Asigna grado "B" a la descripción del servicio
                  associated_against: {
                    system_service: { name: 'A' } # Asigna grado "A" al nombre del sistema asociado
                  },
                  using: {
                    tsearch: { prefix: true }
                  }

  scope :visible_for_user, lambda { |user|
    return all if user&.admin?

    where(restricted_service: false)
  }

  def visible_for_user?(user)
    return true if user&.admin?

    !restricted_service?
  end

  def show_allowed_for?(user)
    return true if user&.admin?
    return false if restricted_service?

    available?
  end

  def caution_notice_for?(user)
    caution_service? && !user&.admin?
  end

  def unit_price_usd(tasa_dolar: nil, unidad_vi: nil)
    return nil unless fixed?

    reference_amount = reference_price_amount
    return nil unless reference_amount.positive?

    bcv_rate = tasa_dolar.to_d
    bcv_rate = TasaCambio.latest_value('Dolar BCV').to_d unless bcv_rate.positive?
    return nil unless bcv_rate.positive?

    reference_rate_bs = reference_rate_to_bs(tasa_dolar: bcv_rate, unidad_vi: unidad_vi)
    return nil unless reference_rate_bs.positive?

    ((reference_amount * reference_rate_bs) / bcv_rate).round(2)
  end

  def unit_price_bs(tasa_dolar: nil, unidad_vi: nil)
    return nil unless fixed?

    reference_amount = reference_price_amount
    return nil unless reference_amount.positive?

    reference_rate_bs = reference_rate_to_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
    return nil unless reference_rate_bs.positive?

    (reference_amount * reference_rate_bs).round(2)
  end

  def total_expense_usd(tasa_dolar: nil, unidad_vi: nil)
    service_expense_structures.sum do |structure|
      structure.total_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
    end.round(2)
  end

  def total_expense_bs(tasa_dolar: nil, unidad_vi: nil)
    service_expense_structures.sum do |structure|
      structure.total_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
    end.round(2)
  end

  private

  def normalize_masked_sale_price
    self.sale_price = parse_masked_decimal(sale_price_before_type_cast)
  end

  def normalize_currency_base_price
    normalized = String(currency_base_price || '').strip
    normalized = DEFAULT_REFERENCE if normalized == LEGACY_USD_REFERENCE

    self.currency_base_price = normalized
  end

  def migrate_legacy_value_units_to_sale_price
    return unless fixed?
    return unless currency_base_price == 'Unidad VI'
    return unless sale_price.to_d.zero?
    return unless value_units.to_d.positive?

    self.sale_price = value_units
  end

  def parse_masked_decimal(raw_value)
    return raw_value if raw_value.is_a?(Numeric) || raw_value.is_a?(BigDecimal)

    compact = String(raw_value || '')
              .strip
              .gsub(/\s/, '')
              .gsub(/[^\d.,-]/, '')
    return nil if compact.blank?

    normalized = if compact.include?(',')
                   compact.gsub('.', '').gsub(',', '.')
                 elsif /^\d{1,3}(\.\d{3})+$/.match?(compact)
                   compact.gsub('.', '')
                 else
                   compact
                 end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end

  def validate_fixed_price_fields
    return unless fixed?

    reference = String(currency_base_price || '').strip
    if reference.blank?
      errors.add(:currency_base_price, 'must be selected for fixed pricing')
      return
    end

    unless valid_currency_reference?(reference)
      errors.add(:currency_base_price, 'must be a registered exchange rate or Bs')
    end

    errors.add(:sale_price, 'must be present for fixed pricing') unless reference_price_amount.positive?
  end

  def validate_visibility_flags
    return unless restricted_service? && caution_service?

    errors.add(:restricted_service, 'no puede combinarse con servicio con precaucion')
    errors.add(:caution_service, 'no puede combinarse con servicio restringido')
  end

  def validate_auto_cost_stock_discount_settings
    return unless auto_cost_stock_discount?

    errors.add(:auto_cost_stock_discount, 'requiere activar la opcion "Conlleva gastos"') unless cost?

    return if service_expense_structures.reject(&:marked_for_destruction?).any?

    errors.add(:auto_cost_stock_discount, 'requiere al menos una estructura de gastos activa')
  end

  def valid_currency_reference?(reference)
    return true if reference == BOLIVAR_REFERENCE

    TasaCambio.latest_for(reference).present?
  end

  def reference_price_amount
    amount = sale_price.to_d
    return amount if amount.positive?

    return value_units.to_d if currency_base_price == 'Unidad VI' && value_units.to_d.positive?

    amount
  end

  def reference_rate_to_bs(tasa_dolar:, unidad_vi: nil)
    reference = String(currency_base_price || '').strip

    return 1.to_d if reference == BOLIVAR_REFERENCE

    if reference == 'Dolar BCV'
      rate = tasa_dolar.to_d
      return rate if rate.positive?

      return TasaCambio.latest_value('Dolar BCV').to_d
    end

    if reference == 'Unidad VI'
      rate = unidad_vi.to_d
      return rate if rate.positive?

      return TasaCambio.latest_value('Unidad VI').to_d
    end

    TasaCambio.latest_value(reference).to_d
  end
end
