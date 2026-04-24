class Cliente < ApplicationRecord
  DOCUMENT_TYPES = %w[V E J G].freeze

  belongs_to :business
  belongs_to :user, optional: true
  has_many :ventas, dependent: :nullify
  has_many :debts, foreign_key: :cliente_id, dependent: :nullify

  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :name, presence: true

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

    {
      "general_product_discount_percent" => general_discount.round(2).to_f,
      "product_rules" => product_rules,
      "service_rules" => service_rules,
      "service_fixed_prices" => service_fixed_prices,
    }
  rescue JSON::ParserError
    {
      "general_product_discount_percent" => 0.0,
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
      normalized["product_rules"].is_a?(Hash) && normalized["product_rules"].any? ||
      normalized["service_rules"].is_a?(Hash) && normalized["service_rules"].any? ||
      normalized["service_fixed_prices"].is_a?(Hash) && normalized["service_fixed_prices"].any?
  end
end
