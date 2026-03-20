class SaleCurrencyReferenceService
  RATE_DESCRIPTION_BY_KEY = {
    usd_rate: 'Dolar BCV',
    eur_rate: 'Euro BCV'
  }.freeze

  def self.sale_reference_date(sale)
    timestamp = sale&.created_at
    return Date.current if timestamp.blank?

    timestamp.in_time_zone('America/Caracas').to_date
  rescue StandardError
    timestamp.to_date
  end

  def self.exchange_rates_for_dates(dates)
    normalized_dates = Array(dates).filter_map { |date| normalize_date(date) }.uniq
    return {} if normalized_dates.empty?

    key_by_description = RATE_DESCRIPTION_BY_KEY.invert
    rates = normalized_dates.index_with { { usd_rate: 0.to_d, eur_rate: 0.to_d } }

    TasaCambio
      .where(description: RATE_DESCRIPTION_BY_KEY.values, fecha_referencia: normalized_dates)
      .order(fecha_referencia: :desc, created_at: :desc)
      .each do |rate|
        key = key_by_description[rate.description]
        next if key.blank?

        day_rates = rates[rate.fecha_referencia]
        next if day_rates.blank?
        next if day_rates[key].to_d.positive?

        day_rates[key] = rate.valor.to_d
      end

    rates
  end

  def initialize(sales)
    @sales = Array(sales).compact
  end

  def rates_by_date
    @rates_by_date ||= begin
      dates = @sales.map { |sale| self.class.sale_reference_date(sale) }
      self.class.exchange_rates_for_dates(dates)
    end
  end

  def totals_by_sale_id
    @totals_by_sale_id ||= @sales.each_with_object({}) do |sale, hash|
      key = sale.id || sale.object_id
      hash[key] = totals_for_sale(sale)
    end
  end

  private

  def totals_for_sale(sale)
    rate_date = self.class.sale_reference_date(sale)
    day_rates = rates_by_date.fetch(rate_date, { usd_rate: 0.to_d, eur_rate: 0.to_d })
    usd_rate = day_rates[:usd_rate].to_d
    eur_rate = day_rates[:eur_rate].to_d
    stored_sale_rate = sale.tasa_dolar.to_d
    effective_usd_rate = stored_sale_rate.positive? ? stored_sale_rate : usd_rate

    base_currency = sale.base_currency.to_s == 'VES' ? 'VES' : 'USD'

    if base_currency == 'VES'
      ves_total = sale.total_bs.to_d
      usd_total = if effective_usd_rate.positive?
                    (ves_total / effective_usd_rate)
                  else
                    sale.total_usd.to_d
                  end
    else
      usd_total = sale.total_usd.to_d
      ves_total = if effective_usd_rate.positive?
                    (usd_total * effective_usd_rate)
                  else
                    sale.total_bs.to_d
                  end
    end

    {
      sale_id: sale.id,
      rate_date: rate_date,
      base_currency: base_currency,
      usd_total: usd_total.round(2),
      ves_total: ves_total.round(2),
      usd_rate: usd_rate.round(4),
      eur_rate: eur_rate.round(4),
      effective_usd_rate: effective_usd_rate.round(4),
      used_fallback_rate: !stored_sale_rate.positive? && usd_rate.positive?
    }
  end

  def self.normalize_date(raw_date)
    return raw_date if raw_date.is_a?(Date)

    raw_date.to_date
  rescue StandardError
    nil
  end

  private_class_method :normalize_date
end
