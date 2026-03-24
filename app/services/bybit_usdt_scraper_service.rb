require 'net/http'
require 'openssl'
require 'uri'
require 'json'
require 'nokogiri'
require 'active_support/time'

class BybitUsdtScraperService
  BYBIT_URL = 'https://www.bybit.com/es-ES/convert/usdt-to-ves/'.freeze
  PAYMENT_LIST_URL = 'https://api2.bybit.com/fiat/public/channel/payment-list'.freeze
  DEFAULT_CRYPTO = 'USDT'.freeze
  DEFAULT_FIAT = 'VES'.freeze
  REQUEST_HEADERS = {
    'User-Agent' => 'Mozilla/5.0 (compatible; BizFlow/1.0)',
    'Accept-Language' => 'es-ES,es;q=0.9,en;q=0.8'
  }.freeze
  RATE_REGEX = /1\s*USDT\s*(?:\u2248|~)\s*([\d.,]+)\s*VES/i

  def self.call
    rate_value = fetch_rate_from_payment_list

    if rate_value.nil?
      html = fetch_html(BYBIT_URL)
      return nil if html.blank?

      html = html.to_s.force_encoding('UTF-8').scrub

      rate_text = extract_rate_text(html)
      return nil if rate_text.blank?

      rate_value = normalize_decimal(rate_text)
    end

    return nil unless rate_value&.positive?

    fecha = Time.current.in_time_zone('Caracas').to_date
    description = resolve_description
    upsert_rate_for_day!(description, rate_value, fecha)

    { usdt: rate_value, fecha_referencia: fecha }
  rescue StandardError => e
    Rails.logger.error "Error en BybitUsdtScraperService: #{e.message}"
    nil
  end

  def self.fetch_html(url, redirect_limit = 5)
    raise ArgumentError, 'Demasiadas redirecciones' if redirect_limit <= 0

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 15

    http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

    request = Net::HTTP::Get.new(uri.request_uri, REQUEST_HEADERS)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      location = response['location']
      return nil if location.blank?

      fetch_html(URI.join(url, location).to_s, redirect_limit - 1)
    else
      Rails.logger.error "Error HTTP en BybitUsdtScraperService: #{response.code} #{response.message}"
      nil
    end
  end

  def self.extract_rate_text(html)
    doc = Nokogiri::HTML(html)

    converter_row = doc.css('.currency-converter-container-list').find do |row|
      left = row.at_css('.currency-converter-container-left')&.text&.strip
      left&.match?(/\A1\s*USDT\z/i)
    end

    converter_value = converter_row&.at_css('.currency-converter-container-right')&.text&.strip
    return converter_value if converter_value.present?

    legacy_node = doc.css('.middle-wrapper').find do |el|
      text = el.text.to_s
      text.include?('USDT') && text.include?('VES')
    end

    legacy_text = legacy_node&.text&.strip
    if legacy_text.present?
      match = legacy_text.match(RATE_REGEX)
      return match[1] if match
    end

    match = html.match(RATE_REGEX)
    match ? match[1] : nil
  end

  def self.fetch_rate_from_payment_list
    uri = URI.parse(PAYMENT_LIST_URL)
    uri.query = URI.encode_www_form(crypto: DEFAULT_CRYPTO, fiat: DEFAULT_FIAT)

    raw = fetch_html(uri.to_s)
    return nil if raw.blank?

    payload = JSON.parse(raw)
    return nil unless payload.is_a?(Hash) && payload['ret_code'].to_i.zero?

    payments = payload.dig('result', 'payments', 'list') || []
    selected = payments.find { |item| item['is_default'] } ||
               payments.find { |item| item['is_recommend'] } ||
               payments.first
    return nil if selected.blank?

    normalize_decimal(selected['price'] || selected['unit_cost'])
  rescue JSON::ParserError => e
    Rails.logger.error "Error JSON en BybitUsdtScraperService: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Error consultando payment-list Bybit: #{e.message}"
    nil
  end

  def self.resolve_description
    existing = TasaCambio.where('LOWER(description) = ?', 'usdt').limit(1).pick(:description)
    return existing if existing.present?

    existing_bybit = TasaCambio.where('LOWER(description) = ?', 'usdt bybit').limit(1).pick(:description)
    return existing_bybit if existing_bybit.present?

    'USDT'
  end

  def self.normalize_decimal(raw_value)
    sanitized = raw_value.to_s.strip
    sanitized = sanitized.gsub('.', '').tr(',', '.') if sanitized.include?(',')
    sanitized = sanitized.gsub(/[^\d.]/, '')
    BigDecimal(sanitized).truncate(2)
  rescue ArgumentError
    nil
  end

  def self.upsert_rate_for_day!(description, value, date)
    rate = TasaCambio.find_or_initialize_by(description: description, fecha_referencia: date)
    rate.valor = value
    rate.symbol ||= TasaCambio.latest_symbol(description) || TasaCambio::DEFAULT_SYMBOLS[description] || 'Bs'
    rate.save!
  end

  private_class_method :fetch_html, :extract_rate_text, :normalize_decimal, :upsert_rate_for_day!, :resolve_description,
                       :fetch_rate_from_payment_list
end
