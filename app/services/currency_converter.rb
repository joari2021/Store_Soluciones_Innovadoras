class CurrencyConverter
  RATE_REFERENCE_BY_CURRENCY = {
    'USD' => 'Dolar BCV',
    'EUR' => 'Euro BCV',
    'USDT' => 'USDT'
  }.freeze

  def self.convert(amount:, from_currency:, to_currency:, on_date: nil)
    from = normalize_currency(from_currency)
    to = normalize_currency(to_currency)
    value = amount.to_d

    return nil unless value.positive? || value.zero?
    return conversion_result(amount: value, rate: 1.to_d) if from == to

    from_rate_to_ves = rate_to_ves(from, on_date: on_date)
    to_rate_to_ves = rate_to_ves(to, on_date: on_date)
    return nil unless from_rate_to_ves.positive? && to_rate_to_ves.positive?

    converted_amount = (value * from_rate_to_ves / to_rate_to_ves)
    rate = value.zero? ? 0.to_d : (converted_amount / value)

    conversion_result(amount: converted_amount, rate: rate)
  end

  def self.rate_to_ves(currency, on_date: nil)
    normalized_currency = normalize_currency(currency)
    return 1.to_d if normalized_currency == 'VES'

    reference = reference_for_currency(normalized_currency)
    return 0.to_d if reference.blank?

    rate_value(reference, on_date: on_date)
  end

  def self.supported_currency?(currency)
    normalized_currency = normalize_currency(currency)
    return true if normalized_currency == 'VES'

    reference_for_currency(normalized_currency).present?
  end

  def self.reference_for_currency(currency)
    normalized_currency = normalize_currency(currency)

    RATE_REFERENCE_BY_CURRENCY[normalized_currency] || begin
      candidate_references(normalized_currency).find do |description|
        TasaCambio.latest_for(description).present?
      end
    end
  end

  def self.candidate_references(currency)
    [
      currency,
      "#{currency} BCV",
      "#{currency} Bybit"
    ]
  end

  def self.conversion_result(amount:, rate:)
    {
      amount: amount.to_d.round(2),
      rate: rate.to_d.round(8)
    }
  end

  def self.normalize_currency(currency)
    currency.to_s.strip.upcase
  end

  def self.rate_value(reference, on_date: nil)
    scope = TasaCambio.where(description: reference)

    reference_date = normalize_reference_date(on_date)
    if reference_date.present?
      historical = scope
                   .where('fecha_referencia <= ?', reference_date)
                   .order(fecha_referencia: :desc, created_at: :desc)
                   .first
      return historical.valor.to_d if historical.present?
    end

    latest_value = scope.order(fecha_referencia: :desc, created_at: :desc).limit(1).pick(:valor)
    latest_value.present? ? latest_value.to_d : 0.to_d
  end

  def self.normalize_reference_date(on_date)
    return nil if on_date.blank?
    return on_date if on_date.is_a?(Date)

    on_date.to_date
  rescue ArgumentError, NoMethodError
    nil
  end

  private_class_method :candidate_references, :conversion_result, :normalize_currency,
                       :rate_value, :normalize_reference_date
end
