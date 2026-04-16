class DiscountSchedule < ApplicationRecord
  belongs_to :business

  enum :applies_to, {
    products: 'products',
    services: 'services'
  }, default: :products, validate: true, prefix: true

  enum :quantity_mode, {
    exact_quantity: 'exact_quantity',
    from_quantity: 'from_quantity'
  }, default: :from_quantity, validate: true, prefix: true

  enum :discount_mode, {
    fixed_amount: 'fixed_amount',
    percent: 'percent'
  }, default: :percent, validate: true, prefix: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :quantity_threshold, numericality: { only_integer: true, greater_than: 0 }
  validates :discount_value, numericality: { greater_than: 0 }
  validate :validate_discount_value_by_mode
  validate :validate_target_presence
  validate :validate_date_window
  validate :validate_applies_to_mode

  before_validation :normalize_target_ids
  before_validation :normalize_targets_by_applies_to

  scope :enabled, -> { where(active: true) }
  scope :active_on, lambda { |date = Date.current|
    where('starts_on IS NULL OR starts_on <= ?', date)
      .where('ends_on IS NULL OR ends_on >= ?', date)
  }

  def active_on?(date)
    return false unless active?
    return false if starts_on.present? && date < starts_on
    return false if ends_on.present? && date > ends_on

    true
  end

  def quantity_rule_label
    return "Cantidad exacta: #{quantity_threshold}" if quantity_mode_exact_quantity?

    "Desde #{quantity_threshold}"
  end

  def discount_label
    return "#{discount_value.to_d.round(2).to_s('F')}%" if discount_mode_percent?

    "Precio fijo #{discount_value.to_d.round(2).to_s('F')}"
  end

  private

  def normalize_target_ids
    self.product_ids = normalize_ids_array(product_ids)
    self.service_ids = normalize_ids_array(service_ids)
  end

  def normalize_ids_array(raw_ids)
    Array(raw_ids)
      .map { |id| id.to_s.strip }
      .reject(&:blank?)
      .select { |id| id.match?(/\A\d+\z/) }
      .map(&:to_i)
      .uniq
      .sort
  end

  def normalize_targets_by_applies_to
    return if applies_to.blank?

    self.service_ids = [] if applies_to_products?
    self.product_ids = [] if applies_to_services?
  end

  def validate_discount_value_by_mode
    return unless discount_mode_percent? && discount_value.to_d > 100.to_d

    errors.add(:discount_value, 'no puede ser mayor a 100 cuando es porcentaje.')
  end

  def validate_target_presence
    if applies_to_products?
      if product_ids.blank?
        errors.add(:product_ids, 'debe incluir un producto.')
      elsif product_ids.size != 1
        errors.add(:product_ids, 'solo permite un producto por regla.')
      end
    end

    if applies_to_services?
      if service_ids.blank?
        errors.add(:service_ids, 'debe incluir un servicio.')
      elsif service_ids.size != 1
        errors.add(:service_ids, 'solo permite un servicio por regla.')
      end
    end
  end

  def validate_applies_to_mode
    return if applies_to_products? || applies_to_services?

    errors.add(:applies_to, 'solo permite productos o servicios.')
  end

  def validate_date_window
    return if starts_on.blank? || ends_on.blank?
    return if ends_on >= starts_on

    errors.add(:ends_on, 'debe ser mayor o igual que la fecha de inicio.')
  end
end