class TasaCambio < ApplicationRecord
  DEFAULT_SYMBOLS = {
    'Dolar BCV' => '$',
    'Euro BCV' => '€',
    'Unidad VI' => 'Bs',
    'USDT Bybit' => 'Bs',
    'USDT' => 'USDT'
  }.freeze

  before_validation :set_default_fecha_referencia
  before_validation :set_default_symbol

  validates :description, presence: true
  validates :valor, presence: true, numericality: { greater_than: 0 }
  validates :fecha_referencia, presence: true
  validates :symbol, presence: true
  validates :fecha_referencia,
            uniqueness: { scope: :description, message: 'ya tiene una tasa registrada para esta descripción' }
  validate :symbol_consistency_for_description

  scope :latest_first, -> { order(fecha_referencia: :desc, created_at: :desc) }

  def self.latest_for(description)
    where(description: description).latest_first.first
  end

  def self.latest_value(description)
    latest_for(description)&.valor
  end

  def self.latest_symbol(description)
    latest_for(description)&.symbol
  end

  def self.latest_values_by_description
    all.order(description: :asc, fecha_referencia: :desc, created_at: :desc).each_with_object({}) do |tasa, hash|
      hash[tasa.description] ||= tasa.valor
    end
  end

  def self.latest_by_description(excluding: [])
    scope = excluding.present? ? where.not(description: excluding) : all

    scope.latest_first.each_with_object({}) do |tasa, hash|
      hash[tasa.description] ||= tasa
    end.values.sort_by(&:description)
  end

  private

  def set_default_fecha_referencia
    self.fecha_referencia ||= Date.current
  end

  def set_default_symbol
    return if symbol.present?

    self.symbol = self.class.latest_symbol(description) || DEFAULT_SYMBOLS[description]
  end

  def symbol_consistency_for_description
    return if description.blank? || symbol.blank?

    existing_symbol = self.class.where(description: description).where.not(id: id).limit(1).pick(:symbol)
    return if existing_symbol.blank? || existing_symbol == symbol

    errors.add(:symbol, "debe ser #{existing_symbol} para la descripción #{description}")
  end
end
