class Service < ApplicationRecord
  include PgSearch::Model

  BOLIVAR_REFERENCE = 'Bs'.freeze
  LEGACY_USD_REFERENCE = '$'.freeze
  DEFAULT_REFERENCE = 'Dolar BCV'.freeze
  RCV_SHARED_ATTRIBUTES = %w[
    physical_requirements
    digital_requirements
    required_data
    personal_steps
    note
    delivery_content
    delivery_time
    delivery_physical_enabled
    delivery_digital_enabled
    warn_digital_only_delivery_in_sales
  ].freeze

  belongs_to :business
  belongs_to :system_service, optional: true
  belongs_to :print_delivery_service, class_name: 'Service', optional: true
  belongs_to :print_delivery_material_surcharge,
             class_name: 'ServicePrintMaterialSurcharge',
             optional: true
  has_one_attached :recarga_image
  has_one_attached :custom_display_image
  has_many :service_managers, dependent: :destroy
  has_many :service_expense_structures, dependent: :destroy
  has_many :service_cost_debts, class_name: 'Debt', dependent: :nullify
  has_many :service_print_coverage_prices, dependent: :destroy
  has_many :service_print_material_surcharges, dependent: :destroy
  has_many :service_print_volume_discounts, dependent: :destroy
  has_many :print_delivery_dependents,
           class_name: 'Service',
           foreign_key: :print_delivery_service_id,
           inverse_of: :print_delivery_service,
           dependent: :nullify

  accepts_nested_attributes_for :service_managers, allow_destroy: true
  accepts_nested_attributes_for :service_expense_structures, allow_destroy: true
  accepts_nested_attributes_for :service_print_coverage_prices, allow_destroy: true
  accepts_nested_attributes_for :service_print_material_surcharges, allow_destroy: true
  accepts_nested_attributes_for :service_print_volume_discounts, allow_destroy: true

  enum :pricing_mode, { fixed: 'fixed', to_agree: 'to_agree' }, default: :fixed, validate: true

  validates :description, presence: true
  validates :sale_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :value_units, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :recarga_min_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :recarga_multiple_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :recarga_profit_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :normalize_masked_sale_price
  before_validation :normalize_currency_base_price
  before_validation :migrate_legacy_value_units_to_sale_price
  before_validation :clear_delivery_configuration_for_printing_service
  before_validation :normalize_recarga_amounts
  before_validation :apply_rcv_shared_template_for_new_record, on: :create
  after_commit :sync_rcv_shared_attributes_to_related_services, on: %i[create update]

  validate :validate_fixed_price_fields
  validate :validate_visibility_flags
  validate :validate_single_active_expense_structure_for_sales
  validate :validate_delivery_presentations
  validate :validate_physical_printing_configuration
  validate :validate_print_delivery_extra_products
  validate :validate_print_coverage_prices_for_print_services
  validate :validate_print_material_surcharges_for_print_services

  before_validation :normalize_print_delivery_pages
  before_validation :normalize_print_delivery_extra_products
  before_validation :normalize_print_delivery_material_surcharge
  before_validation :normalize_print_sale_description

  scope :printing_type_candidates, lambda {
    joins(:system_service)
      .where('system_services.name ILIKE :q1 OR system_services.name ILIKE :q2', q1: '%impresion%', q2: '%impresión%')
  }

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

  def self.rcv_scope
    joins(:system_service).where('system_services.name ILIKE ?', '%rcv%')
  end

  def self.latest_rcv_template_for_business(business)
    return nil unless business

    business.services
            .rcv_scope
            .where.not(id: nil)
            .order(updated_at: :desc, id: :desc)
            .first
  end

  def self.rcv_shared_template_attributes_for_business(business)
    template = latest_rcv_template_for_business(business)
    return {} unless template

    template.attributes.slice(*RCV_SHARED_ATTRIBUTES)
  end

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

  def total_expense_usd(tasa_dolar: nil, unidad_vi: nil, active_only: false)
    structures = expense_structures_for_totals(active_only: active_only)

    structures.sum do |structure|
      structure.total_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
    end.round(2)
  end

  def total_expense_bs(tasa_dolar: nil, unidad_vi: nil, active_only: false)
    structures = expense_structures_for_totals(active_only: active_only)

    structures.sum do |structure|
      structure.total_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
    end.round(2)
  end

  def active_expense_structures_for_sales
    expense_structures_for_totals(active_only: true)
  end

  def printing_type_service?
    normalized_system_name = I18n.transliterate(system_service&.name.to_s).downcase.strip
    normalized_system_name.include?('impresion')
  end

  def lamination_type_service?
    normalized_system_name = I18n.transliterate(system_service&.name.to_s).downcase.strip
    normalized_system_name.include?('plastificacion')
  end

  def rcv_service?
    system_service&.rcv_system?
  end

  def print_sale_display_name
    print_sale_description.to_s.strip.presence || description.to_s
  end

  def normalized_print_delivery_pages
    Array(print_delivery_pages).filter_map do |raw_page|
      row = raw_page.is_a?(Hash) ? raw_page.deep_stringify_keys : {}
      coverage = row['coverage_percent'].to_d.round(2)
      next unless coverage.positive?

      page_print_type_service_id = row['print_type_service_id'].to_i
      if page_print_type_service_id <= 0 && print_delivery_service_id.present?
        page_print_type_service_id = print_delivery_service_id
      end

      page_material_surcharge_id = row['material_surcharge_id'].to_i
      if page_material_surcharge_id <= 0 && print_delivery_material_surcharge_id.present?
        page_material_surcharge_id = print_delivery_material_surcharge_id
      end

      includes_lamination = ActiveModel::Type::Boolean.new.cast(row['includes_lamination'])
      lamination_service_id = row['lamination_service_id'].to_i
      lamination_service_id = nil unless includes_lamination && lamination_service_id.positive?

      {
        'page_number' => row['page_number'].to_i.positive? ? row['page_number'].to_i : 1,
        'coverage_percent' => coverage.to_f,
        'print_type_service_id' => page_print_type_service_id.positive? ? page_print_type_service_id : nil,
        'material_surcharge_id' => page_material_surcharge_id.positive? ? page_material_surcharge_id : nil,
        'includes_lamination' => includes_lamination,
        'lamination_service_id' => lamination_service_id
      }
    end.sort_by { |row| row['page_number'].to_i }
  end

  def normalized_print_delivery_extra_products
    rows = Array(raw_print_delivery_extra_products).filter_map do |raw_row|
      row = raw_row.is_a?(Hash) ? raw_row.deep_stringify_keys : {}
      product_id = row['product_id'].to_i
      variation_id = row['variation_id'].to_i
      quantity = row['quantity'].to_d.round(2)
      next unless product_id.positive? && quantity.positive?

      {
        'product_id' => product_id,
        'variation_id' => variation_id.positive? ? variation_id : nil,
        'quantity' => quantity.to_f,
        'breakdown_in_invoice' => ActiveModel::Type::Boolean.new.cast(row['breakdown_in_invoice'])
      }
    end

    rows.sort_by { |row| row['product_id'].to_i }
  end

  def resolved_printing_cost_bs
    return 0.to_d unless delivery_physical_enabled?
    return 0.to_d if normalized_print_delivery_pages.empty?

    services_by_id = business
                     .services
                     .includes(:service_print_coverage_prices)
                     .where(id: normalized_print_delivery_pages.filter_map do |row|
                              row['print_type_service_id'].to_i if row['print_type_service_id'].to_i.positive?
                            end)
                     .index_by(&:id)

    normalized_print_delivery_pages.sum do |row|
      coverage = row['coverage_percent'].to_d
      next 0.to_d unless coverage.positive?

      print_type_service = services_by_id[row['print_type_service_id'].to_i]
      next 0.to_d unless print_type_service

      prices = print_type_service.service_print_coverage_prices.ordered_by_coverage.to_a
      next 0.to_d if prices.empty?

      match = prices.find { |price| price.coverage_percent.to_d >= coverage }
      match ||= prices.last
      match&.price_bs.to_d
    end.round(2)
  end

  private

  def apply_rcv_shared_template_for_new_record
    return unless rcv_service?

    template = self.class.latest_rcv_template_for_business(business)
    return unless template

    RCV_SHARED_ATTRIBUTES.each do |attribute|
      self[attribute] = template[attribute]
    end
  end

  def sync_rcv_shared_attributes_to_related_services
    return unless business_id.present?
    return unless rcv_service?

    changed_shared_attributes = saved_changes.keys & RCV_SHARED_ATTRIBUTES
    changed_shared_attributes = RCV_SHARED_ATTRIBUTES if previous_changes.key?('id')
    return if changed_shared_attributes.empty?

    attributes_to_sync = changed_shared_attributes.index_with { |attribute| self[attribute] }
    business.services
            .where.not(id: id)
            .joins(:system_service)
            .where("system_services.name ILIKE ?", "%rcv%")
            .update_all(attributes_to_sync.merge(updated_at: Time.current))
  end

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

  def normalize_recarga_amounts
    self.recarga_min_amount = parse_masked_decimal(recarga_min_amount_before_type_cast)
    self.recarga_multiple_amount = parse_masked_decimal(recarga_multiple_amount_before_type_cast)
    self.recarga_profit_percent = parse_masked_decimal(recarga_profit_percent_before_type_cast)
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

  def validate_single_active_expense_structure_for_sales
    return if expense_structures_for_totals(active_only: true).size <= 1

    errors.add(:base, 'Solo puedes marcar una estructura de gastos como activa en ventas.')
  end

  def validate_delivery_presentations
    return if printing_type_service?
    return if lamination_type_service?
    return if delivery_physical_enabled? || delivery_digital_enabled?

    errors.add(:base, 'Debes seleccionar al menos una presentacion de entrega (fisico o digital).')
  end

  def validate_physical_printing_configuration
    return if printing_type_service?
    return unless delivery_physical_enabled?

    pages = normalized_print_delivery_pages
    if pages.empty?
      errors.add(:print_delivery_pages, 'debe incluir al menos una pagina para entrega fisica.')
      return
    end

    page_print_type_ids = pages.filter_map do |row|
      row['print_type_service_id'].to_i if row['print_type_service_id'].to_i.positive?
    end.uniq
    page_material_ids = pages.filter_map do |row|
      row['material_surcharge_id'].to_i if row['material_surcharge_id'].to_i.positive?
    end.uniq
    page_lamination_ids = pages.filter_map do |row|
      row['lamination_service_id'].to_i if row['lamination_service_id'].to_i.positive?
    end.uniq

    print_type_services = business
                          .services
                          .includes(:service_print_coverage_prices)
                          .where(id: page_print_type_ids)
                          .index_by(&:id)
    material_rows = ServicePrintMaterialSurcharge
                    .includes(:producto)
                    .where(id: page_material_ids)
                    .index_by(&:id)
    lamination_services = business
                          .services
                          .includes(:system_service)
                          .where(id: page_lamination_ids)
                          .index_by(&:id)

    pages.each do |row|
      page_number = row['page_number'].to_i
      coverage = row['coverage_percent'].to_d
      page_type_id = row['print_type_service_id'].to_i
      page_material_id = row['material_surcharge_id'].to_i

      if page_type_id <= 0
        errors.add(:print_delivery_pages, "la pagina #{page_number} debe seleccionar un tipo de impresion.")
        next
      end

      print_type_service = print_type_services[page_type_id]
      if print_type_service.blank? || !print_type_service.printing_type_service?
        errors.add(:print_delivery_pages, "la pagina #{page_number} tiene un tipo de impresion invalido.")
        next
      end

      prices = print_type_service.service_print_coverage_prices.ordered_by_coverage.to_a
      if prices.empty?
        errors.add(:print_delivery_pages,
                   "la pagina #{page_number} usa #{print_type_service.description}, pero ese tipo no tiene precios por cobertura.")
        next
      end

      unless prices.any? { |price| price.coverage_percent.to_d >= coverage }
        errors.add(:print_delivery_pages,
                   "no existe precio por cobertura para #{coverage.to_f.round(2)}% en #{print_type_service.description} (pagina #{page_number}).")
      end

      if page_material_id <= 0
        errors.add(:print_delivery_pages, "la pagina #{page_number} debe seleccionar un material.")
        next
      end

      material_row = material_rows[page_material_id]
      if material_row.blank? || material_row.service_id != print_type_service.id
        errors.add(:print_delivery_pages,
                   "la pagina #{page_number} tiene un material que no pertenece al tipo #{print_type_service.description}.")
        next
      end

      if material_row.producto.blank?
        errors.add(:print_delivery_pages, "la pagina #{page_number} tiene un material invalido.")
      end

      includes_lamination = ActiveModel::Type::Boolean.new.cast(row['includes_lamination'])
      next unless includes_lamination

      lamination_service_id = row['lamination_service_id'].to_i
      if lamination_service_id <= 0
        errors.add(:print_delivery_pages,
                   "la pagina #{page_number} debe seleccionar un servicio de plastificacion.")
        next
      end

      lamination_service = lamination_services[lamination_service_id]
      lamination_system = I18n.transliterate(lamination_service&.system_service&.name.to_s).downcase

      unless lamination_service.present? && lamination_system.include?('plastificacion')
        errors.add(:print_delivery_pages,
                   "la pagina #{page_number} tiene un servicio de plastificacion invalido.")
      end
    end
  end

  def validate_print_delivery_extra_products
    return unless supports_print_delivery_extra_products?
    return unless delivery_physical_enabled?

    rows = normalized_print_delivery_extra_products
    return if rows.empty?

    product_ids = rows.map { |row| row['product_id'].to_i }.uniq
    products_by_id = business.productos.includes(:product_variations).where(id: product_ids).index_by(&:id)
    valid_ids = products_by_id.keys
    missing_ids = product_ids - valid_ids
    if missing_ids.any?
      errors.add(:print_delivery_extra_products,
                 'incluye productos adicionales invalidos para este negocio.')
      return
    end

    rows.each do |row|
      product = products_by_id[row['product_id'].to_i]
      next unless product

      variation_id = row['variation_id'].to_i
      if variation_id <= 0
        errors.add(:print_delivery_extra_products,
                   "debe seleccionar variacion para #{product.descripcion}.")
        next
      end

      variation_belongs = product.product_variations.any? { |variation| variation.id == variation_id }
      next if variation_belongs

      errors.add(:print_delivery_extra_products,
                 "incluye una variacion invalida para #{product.descripcion}.")
    end

    duplicated = rows
                 .group_by { |row| [row['product_id'].to_i, row['variation_id'].to_i] }
                 .values
                 .any? { |group| group.size > 1 }
    return unless duplicated

    errors.add(:print_delivery_extra_products,
               'no puede repetir el mismo producto adicional con la misma variacion en la presentacion fisica.')
  end

  def validate_print_coverage_prices_for_print_services
    return unless printing_type_service?

    rows = service_print_coverage_prices.reject(&:marked_for_destruction?)
    return if rows.empty?

    duplicated = rows.group_by do |row|
      row.coverage_percent.to_d.round(2).to_s('F')
    end.values.any? { |group| group.size > 1 }
    errors.add(:service_print_coverage_prices, 'no puede repetir el mismo porcentaje de cobertura.') if duplicated
  end

  def validate_print_material_surcharges_for_print_services
    return unless printing_type_service? || lamination_type_service?

    rows = service_print_material_surcharges.reject(&:marked_for_destruction?)
    if lamination_type_service? && rows.empty?
      errors.add(:service_print_material_surcharges,
                 'debe configurar al menos un material para servicios de plastificacion.')
      return
    end

    return unless lamination_type_service?

    duplicated = rows
                 .select { |row| row.producto_id.present? }
                 .group_by { |row| row.producto_id.to_i }
                 .values
                 .any? { |group| group.size > 1 }

    errors.add(:service_print_material_surcharges, 'no puede repetir el mismo material.') if duplicated
  end

  def clear_delivery_configuration_for_printing_service
    return unless printing_type_service? || lamination_type_service?

    self.delivery_physical_enabled = false
    self.delivery_digital_enabled = false
    self.print_delivery_service = nil
    self.print_delivery_material_surcharge = nil
    self.print_delivery_pages = []
    self.print_delivery_extra_products = [] if supports_print_delivery_extra_products?
  end

  def normalize_print_delivery_pages
    self.print_delivery_pages = normalized_print_delivery_pages
  end

  def normalize_print_delivery_extra_products
    return unless supports_print_delivery_extra_products?

    unless delivery_physical_enabled?
      self.print_delivery_extra_products = []
      return
    end

    self.print_delivery_extra_products = normalized_print_delivery_extra_products
  end

  def normalize_print_delivery_material_surcharge
    unless delivery_physical_enabled?
      self.print_delivery_material_surcharge = nil
      return
    end

    return if print_delivery_service_id.blank? || print_delivery_material_surcharge_id.blank?

    return unless print_delivery_material_surcharge&.service_id != print_delivery_service_id

    self.print_delivery_material_surcharge = nil
  end

  def normalize_print_sale_description
    self.print_sale_description = print_sale_description.to_s.strip.presence
  end

  def raw_print_delivery_extra_products
    return [] unless supports_print_delivery_extra_products?

    read_attribute(:print_delivery_extra_products)
  rescue StandardError
    []
  end

  def supports_print_delivery_extra_products?
    self.class.column_names.include?('print_delivery_extra_products')
  end

  def expense_structures_for_totals(active_only:)
    structures = service_expense_structures.reject(&:marked_for_destruction?)
    return structures unless active_only

    structures.select { |structure| ActiveModel::Type::Boolean.new.cast(structure.active_for_sales) }
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
