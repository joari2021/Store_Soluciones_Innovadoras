require 'net/http'
require 'openssl'
require 'uri'
require 'nokogiri'
require 'active_support/time'

class BcvScraperService
  BCV_URL = 'https://www.bcv.org.ve'.freeze
  INSECURE_SSL_FALLBACK_ENV = 'BCV_ALLOW_INSECURE_SSL_FALLBACK'.freeze
  REQUEST_HEADERS = {
    'User-Agent' => 'Mozilla/5.0 (compatible; BizFlow/1.0)'
  }.freeze
  PROJECT_CA_FILES = [
    Rails.root.join('config/certs/SectigoPublicServerAuthenticationCADVR36.pem').to_s,
    Rails.root.join('config/certs/SectigoPublicServerAuthenticationRootR46.pem').to_s
  ].freeze

  def self.call
    html = fetch_html_with_ssl_fallback(BCV_URL)
    return nil if html.blank?

    doc = Nokogiri::HTML(html)

    dato_dolar = doc.at_css('#dolar strong')&.text&.strip
    dato_euro = doc.at_css('#euro strong')&.text&.strip
    fecha_valor = extract_fecha_valor(doc)
    return nil if dato_dolar.blank? || dato_euro.blank? || fecha_valor.blank?

    tasa_valor_dolar = normalize_decimal(dato_dolar)
    tasa_valor_euro = normalize_decimal(dato_euro)
    latest_dolar = latest_reference_date_for('Dolar BCV')
    latest_euro = latest_reference_date_for('Euro BCV')

    if latest_dolar.present? && latest_dolar >= fecha_valor && latest_euro.present? && latest_euro >= fecha_valor
      mark_ssl_success
      return { status: :up_to_date, fecha_referencia: fecha_valor,
               ultima_fecha: [latest_dolar, latest_euro].compact.max }
    end

    backfill_rate_for('Dolar BCV', tasa_valor_dolar, latest_dolar, fecha_valor)
    backfill_rate_for('Euro BCV', tasa_valor_euro, latest_euro, fecha_valor)

    mark_ssl_success

    { status: :updated, dolar_bcv: tasa_valor_dolar, euro_bcv: tasa_valor_euro, fecha_referencia: fecha_valor }
  rescue OpenSSL::SSL::SSLError => e
    mark_ssl_failure(e.message)
    Rails.logger.error "Error SSL en BcvScraperService: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Error en BcvScraperService: #{e.message}"
    nil
  end

  def self.fetch_html_with_ssl_fallback(url, redirect_limit = 5)
    fetch_html(url, redirect_limit: redirect_limit)
  rescue OpenSSL::SSL::SSLError => e
    raise unless retry_with_insecure_ssl?(e)

    Rails.logger.warn("BCV scraper: reintentando sin verificacion SSL por error de certificado: #{e.message}")
    fetch_html(url, redirect_limit: redirect_limit, insecure_ssl: true)
  rescue StandardError
    raise
  end

  def self.fetch_html(url, redirect_limit: 5, insecure_ssl: false)
    raise ArgumentError, 'Demasiadas redirecciones' if redirect_limit <= 0

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 15

    if http.use_ssl?
      if insecure_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = certificate_store
      end
    end

    request = Net::HTTP::Get.new(uri.request_uri, REQUEST_HEADERS)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      location = response['location']
      return nil if location.blank?

      fetch_html(URI.join(url, location).to_s, redirect_limit: redirect_limit - 1, insecure_ssl: insecure_ssl)
    else
      Rails.logger.error "Error HTTP en BcvScraperService: #{response.code} #{response.message}"
      nil
    end
  end

  def self.retry_with_insecure_ssl?(error)
    return false unless insecure_ssl_fallback_enabled?

    message = error.message.to_s.downcase
    message.include?('certificate verify failed') || message.include?('unable to get local issuer certificate')
  end

  def self.insecure_ssl_fallback_enabled?
    raw = ENV.fetch(INSECURE_SSL_FALLBACK_ENV, 'true')
    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def self.certificate_store
    store = OpenSSL::X509::Store.new
    store.set_default_paths

    PROJECT_CA_FILES.each do |ca_file|
      if File.exist?(ca_file)
        store.add_file(ca_file)
      else
        Rails.logger.warn "Certificado no encontrado para BCV: #{ca_file}"
      end
    end

    custom_ca_bundle = ENV['BCV_CA_BUNDLE_PATH'].to_s.strip
    if custom_ca_bundle.present? && File.exist?(custom_ca_bundle)
      store.add_file(custom_ca_bundle)
    elsif custom_ca_bundle.present?
      Rails.logger.warn "BCV_CA_BUNDLE_PATH no existe: #{custom_ca_bundle}"
    end

    store
  end

  def self.mark_ssl_failure(message)
    ScraperStatus.mark_bcv_ssl_failure!(message: message, occurred_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "No se pudo guardar estado SSL BCV (fallo): #{e.message}"
  end

  def self.mark_ssl_success
    ScraperStatus.mark_bcv_ssl_success!(occurred_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "No se pudo guardar estado SSL BCV (exito): #{e.message}"
  end

  def self.normalize_decimal(raw_value)
    text = raw_value.to_s.strip
    numeric = text.gsub(/[^\d,\.]/, '')

    raise ArgumentError, "valor BCV invalido: #{raw_value.inspect}" if numeric.blank?

    if numeric.include?(',') && numeric.include?('.')
      # If both separators exist, the right-most one is treated as decimal separator.
      if numeric.rindex(',') > numeric.rindex('.')
        normalized = numeric.delete('.').tr(',', '.')
      else
        normalized = numeric.delete(',')
      end
    elsif numeric.include?(',')
      normalized = numeric.delete('.').tr(',', '.')
    else
      # If multiple dots exist, treat only the last one as decimal separator.
      segments = numeric.split('.')
      normalized = if segments.size > 2
                     "#{segments[0..-2].join}.#{segments[-1]}"
                   else
                     numeric
                   end
    end

    BigDecimal(normalized).truncate(2)
  end

  def self.extract_fecha_valor(doc)
    node = doc.at_css('div.pull-right.dinpro.center span.date-display-single')
    raw = node&.[]('content') || node&.text
    return nil if raw.blank?

    zone = ActiveSupport::TimeZone['Caracas'] || Time.zone
    parsed = zone&.parse(raw)
    return parsed.to_date if parsed

    Date.parse(raw)
  rescue ArgumentError
    nil
  end

  def self.latest_reference_date_for(description)
    normalized = description.to_s.strip.downcase
    TasaCambio.where('LOWER(TRIM(description)) = ?', normalized).maximum(:fecha_referencia)
  end

  def self.backfill_rate_for(description, value, last_date, target_date)
    start_date = last_date.present? ? last_date.to_date + 1.day : target_date
    return if start_date > target_date

    (start_date..target_date).each do |fecha|
      upsert_rate_for_day!(description, value, fecha)
    end
  end

  def self.upsert_rate_for_day!(description, value, date)
    rate = TasaCambio.find_or_initialize_by(description: description, fecha_referencia: date)
    rate.valor = value
    rate.symbol ||= TasaCambio.latest_symbol(description) || TasaCambio::DEFAULT_SYMBOLS[description]
    rate.save!
  end

  private_class_method :normalize_decimal, :upsert_rate_for_day!, :fetch_html, :fetch_html_with_ssl_fallback,
                       :certificate_store, :mark_ssl_failure, :mark_ssl_success, :extract_fecha_valor,
                       :latest_reference_date_for, :backfill_rate_for, :retry_with_insecure_ssl?,
                       :insecure_ssl_fallback_enabled?
end
