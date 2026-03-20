require 'test_helper'
require 'securerandom'

class SaleCurrencyReferenceServiceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'uses stored sale rate for totals even when day rate differs' do
    business = Business.create!(name: "Negocio tasas #{SecureRandom.hex(3)}")

    sale_day = Date.new(2026, 2, 1)
    later_day = Date.new(2026, 3, 1)

    TasaCambio.create!(description: 'Dolar BCV', valor: 70, fecha_referencia: sale_day, symbol: '$')
    TasaCambio.create!(description: 'Dolar BCV', valor: 100, fecha_referencia: later_day, symbol: '$')
    TasaCambio.create!(description: 'Euro BCV', valor: 80, fecha_referencia: sale_day, symbol: 'EUR')

    venta = business.ventas.create!(
      status: 'paid',
      vat_mode: 'none',
      vat_rate: 0.16,
      base_currency: 'VES',
      tasa_dolar: 65
    )

    sale_timestamp = Time.use_zone('America/Caracas') { Time.zone.local(2026, 2, 1, 12, 0, 0) }
    venta.update_columns(
      total_bs: 2000,
      total_usd: 30.77,
      subtotal_usd: 30.77,
      vat_usd: 0,
      created_at: sale_timestamp,
      updated_at: sale_timestamp
    )

    result = SaleCurrencyReferenceService.new([venta]).totals_by_sale_id.fetch(venta.id)

    assert_equal sale_day, result[:rate_date]
    assert_equal BigDecimal('70.0'), result[:usd_rate]
    assert_equal BigDecimal('80.0'), result[:eur_rate]
    assert_equal BigDecimal('65.0'), result[:effective_usd_rate]
    assert_equal BigDecimal('30.77'), result[:usd_total]
    assert_equal BigDecimal('2000.0'), result[:ves_total]
    refute result[:used_fallback_rate]
  end

  test 'falls back to day rate when sale has no stored rate' do
    business = Business.create!(name: "Negocio tasas legado #{SecureRandom.hex(3)}")

    sale_day = Date.new(2026, 2, 10)

    TasaCambio.create!(description: 'Dolar BCV', valor: 50, fecha_referencia: sale_day, symbol: '$')

    venta = business.ventas.create!(
      status: 'paid',
      vat_mode: 'none',
      vat_rate: 0.16,
      base_currency: 'USD',
      tasa_dolar: 0
    )

    sale_timestamp = Time.use_zone('America/Caracas') { Time.zone.local(2026, 2, 10, 10, 0, 0) }
    venta.update_columns(
      total_usd: 10,
      subtotal_usd: 10,
      vat_usd: 0,
      total_bs: 500,
      created_at: sale_timestamp,
      updated_at: sale_timestamp
    )

    result = SaleCurrencyReferenceService.new([venta]).totals_by_sale_id.fetch(venta.id)

    assert_equal BigDecimal('50.0'), result[:effective_usd_rate]
    assert_equal BigDecimal('10.0'), result[:usd_total]
    assert_equal BigDecimal('500.0'), result[:ves_total]
    assert result[:used_fallback_rate]
  end
end
