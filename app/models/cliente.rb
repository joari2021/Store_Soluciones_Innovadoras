class Cliente < ApplicationRecord
  DOCUMENT_TYPES = %w[V E J G].freeze

  belongs_to :business
  belongs_to :user, optional: true
  has_many :ventas, dependent: :nullify
  has_many :debts, foreign_key: :cliente_id, dependent: :nullify

  before_validation :normalize_document_and_phone

  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :name, presence: true
  validates :phone, presence: true, format: { with: /\A\d{11}\z/, message: 'debe tener exactamente 11 digitos' }

  validate :document_number_forward_validation
  validate :document_uniqueness_forward_only

  def self.normalize_benefits_config(raw_config)
    payload = if raw_config.is_a?(String)
        JSON.parse(raw_config)
      elsif raw_config.is_a?(Hash)
        raw_config
      else
        {}
      end

    payload = payload.deep_stringify_keys

    general_discount = payload["general_product_discount_percent"].to_d
    general_discount = 0.to_d unless general_discount.positive?
    general_discount = 100.to_d if general_discount > 100

    product_rules = {}
    raw_product_rules = payload["product_rules"]
    if raw_product_rules.is_a?(Hash)
      raw_product_rules.each do |product_id, rule|
        next unless product_id.to_s.strip.present?
        next unless rule.is_a?(Hash)

        mode = rule["mode"].to_s.strip.downcase
        next unless %w[fixed percent].include?(mode)

        value = rule["value"].to_d
        next unless value.positive?

        if mode == "percent"
          value = 100.to_d if value > 100
        end

        product_rules[product_id.to_s] = {
          "mode" => mode,
          "value" => value.round(2).to_f,
        }
      end
    end

    service_rules = {}
    raw_service_rules = payload["service_rules"]
    if raw_service_rules.is_a?(Hash)
      raw_service_rules.each do |service_id, rule|
        next unless service_id.to_s.strip.present?
        next unless rule.is_a?(Hash)

        mode = rule["mode"].to_s.strip.downcase
        next unless %w[fixed percent].include?(mode)

        value = rule["value"].to_d
        next unless value.positive?

        value = 100.to_d if mode == "percent" && value > 100

        service_rules[service_id.to_s] = {
          "mode" => mode,
          "value" => value.round(2).to_f,
        }
      end
    end

    raw_service_prices = payload["service_fixed_prices"]
    if raw_service_prices.is_a?(Hash)
      raw_service_prices.each do |service_id, amount|
        next unless service_id.to_s.strip.present?
        next if service_rules.key?(service_id.to_s)

        fixed_amount = amount.to_d
        next unless fixed_amount.positive?

        service_rules[service_id.to_s] = {
          "mode" => "fixed",
          "value" => fixed_amount.round(2).to_f,
        }
      end
    end

    service_fixed_prices = service_rules.each_with_object({}) do |(service_id, rule), hash|
      next unless rule.is_a?(Hash)
      next unless rule["mode"].to_s == "fixed"

      value = rule["value"].to_d
      next unless value.positive?

      hash[service_id] = value.round(2).to_f
    end

    cost_pricing_enabled = ActiveModel::Type::Boolean.new.cast(payload["cost_pricing_enabled"])

    {
      "general_product_discount_percent" => general_discount.round(2).to_f,
      "cost_pricing_enabled" => cost_pricing_enabled,
      "product_rules" => product_rules,
      "service_rules" => service_rules,
      "service_fixed_prices" => service_fixed_prices,
    }
  rescue JSON::ParserError
    {
      "general_product_discount_percent" => 0.0,
      "cost_pricing_enabled" => false,
      "product_rules" => {},
      "service_rules" => {},
      "service_fixed_prices" => {},
    }
  end

  def document_label
    return document_type if document_number.blank?

    "#{document_type}-#{document_number}"
  end

  def normalized_benefits_config
    self.class.normalize_benefits_config(benefits_config)
  end

  def has_special_benefits?
    normalized = normalized_benefits_config
    normalized["general_product_discount_percent"].to_d.positive? ||
      ActiveModel::Type::Boolean.new.cast(normalized["cost_pricing_enabled"]) ||
      normalized["product_rules"].is_a?(Hash) && normalized["product_rules"].any? ||
      normalized["service_rules"].is_a?(Hash) && normalized["service_rules"].any? ||
      normalized["service_fixed_prices"].is_a?(Hash) && normalized["service_fixed_prices"].any?
  end

  private

  def normalize_document_and_phone
    self.document_type = document_type.to_s.strip.upcase
    self.document_number = document_number.to_s.gsub(/\D/, '')
    self.phone = phone.to_s.gsub(/\D/, '')
  end

  def document_number_forward_validation
    should_validate_document = new_record? || will_save_change_to_document_type? || will_save_change_to_document_number?
    return unless should_validate_document

    if document_number.blank?
      errors.add(:document_number, 'no puede estar en blanco')
      return
    end

    return if document_type.blank?

    case document_type
    when 'V'
      return if document_number.match?(/\A\d{6,8}\z/)

      errors.add(:document_number, 'para V debe tener entre 6 y 8 digitos')
    when 'E'
      return if document_number.match?(/\A\d{8}\z/)

      errors.add(:document_number, 'para E debe tener exactamente 8 digitos')
    when 'J'
      return if document_number.match?(/\A\d{9}\z/)

      errors.add(:document_number, 'para J debe tener exactamente 9 digitos')
    end
  end

  def document_uniqueness_forward_only
    return if document_type.blank? || document_number.blank? || business_id.blank?

    scope = self.class.where(business_id: business_id, document_type: document_type, document_number: document_number)

    if persisted?
      # Permite conservar duplicados legacy si no se cambia el documento.
      document_changed = will_save_change_to_document_type? || will_save_change_to_document_number?
      return unless document_changed

      scope = scope.where.not(id: id)
      return unless scope.exists?

      errors.add(:document_number, 'ya existe para ese tipo de documento')
      return
    end

    return unless scope.exists?

    errors.add(:document_number, 'ya existe para ese tipo de documento')
  end
end
