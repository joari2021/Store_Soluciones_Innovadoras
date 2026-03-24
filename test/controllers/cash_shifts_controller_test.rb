require 'test_helper'
require 'securerandom'

class CashShiftsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ['users']
  fixtures :users

  setup do
    @business = Business.create!(name: "Negocio Turnos #{SecureRandom.hex(4)}")

    @opener_user, @opener_password = create_manager_user!(business: @business, prefix: 'open')
    @other_user, @other_password = create_manager_user!(business: @business, prefix: 'other')

    @cash_shift = @business.cash_shifts.create!(
      opened_by: @opener_user,
      status: 'open',
      opened_at: Time.current,
      opening_balance_ves: 0,
      opening_balance_usd: 0
    )
  end

  test 'opener user can close cash shift' do
    login!(@opener_user, @opener_password)

    patch close_cash_shift_path(@cash_shift), params: {
      cash_shift: {
        declared_closing_ves: '120.50',
        declared_closing_usd: '25.00',
        closing_notes: 'Cierre correcto'
      }
    }

    assert_redirected_to cash_shift_path(@cash_shift)

    @cash_shift.reload
    assert @cash_shift.closed?
    assert_equal @opener_user.id, @cash_shift.closed_by_id
  end

  test 'different user cannot close cash shift' do
    login!(@other_user, @other_password)

    patch close_cash_shift_path(@cash_shift), params: {
      cash_shift: {
        declared_closing_ves: '90.00',
        declared_closing_usd: '10.00',
        closing_notes: 'Intento no autorizado'
      }
    }

    assert_redirected_to cash_shift_path(@cash_shift)

    @cash_shift.reload
    assert @cash_shift.open?
    assert_nil @cash_shift.closed_by_id
  end

  test 'close processes biopago settlement automatically from shift verification' do
    login!(@opener_user, @opener_password)

    settlement_bank = @business.accounts.create!(
      name: 'Banco receptor cierre',
      account_type: 'bank_account',
      currency: 'VES',
      balance: 0,
      active: true,
      theme_color: 'sky',
      is_primary: true
    )

    biopago_account = @business.accounts.create!(
      name: 'Biopago',
      account_type: 'biopago',
      currency: 'VES',
      balance: 0,
      active: true,
      theme_color: 'emerald',
      settlement_account: settlement_bank
    )

    sale = @business.ventas.create!(
      status: 'paid',
      vat_mode: 'none',
      vat_rate: 0.16,
      base_currency: 'USD',
      tasa_dolar: 40,
      cash_shift: @cash_shift,
      user: @opener_user
    )
    sale.update_columns(
      subtotal_usd: 10,
      vat_usd: 0,
      total_usd: 10,
      total_bs: 400,
      created_at: Time.current,
      updated_at: Time.current
    )

    sale.venta_payments.create!(
      payment_method: 'biopago',
      account: biopago_account,
      amount_usd: 10,
      amount_original: 400,
      currency: 'VES',
      payment_kind: 'in'
    )

    biopago_account.account_movements.create!(
      movement_kind: 'income',
      amount: 400,
      description: "Ingreso venta ##{sale.id} [VENTA:#{sale.id}]",
      occurred_at: Time.current
    )

    assert_difference('AccountSettlement.count', 1) do
      patch close_cash_shift_path(@cash_shift), params: {
        cash_shift: {
          close_verification_rows: [
            {
              account_id: biopago_account.id,
              account_name: biopago_account.name,
              account_type: 'biopago',
              currency: 'VES',
              expected_amount: '400.00',
              declared_amount: '390.00'
            }
          ]
        }
      }
    end

    assert_redirected_to cash_shift_path(@cash_shift)

    settlement = AccountSettlement.order(:id).last
    assert_equal biopago_account.id, settlement.account_id
    assert settlement.processed?
    assert_equal BigDecimal('390.0'), settlement.credited_amount.to_d
    assert_equal BigDecimal('10.0'), settlement.commission_amount.to_d
    assert_equal 2, settlement_bank.account_movements.where(payment_method: 'settlement').count
  end

  test 'create returns existing open shift when one is already active' do
    login!(@opener_user, @opener_password)

    assert_no_difference('CashShift.count') do
      post cash_shifts_path, as: :json
    end

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_match(/Ya existe un turno abierto/i, payload.fetch('error'))
    assert_equal ventas_path, payload.fetch('redirect_url')
    assert_equal cash_shift_path(@cash_shift), payload.fetch('cash_shift_url')
  end

  test 'create opens shift when scraper updates rates' do
    login!(@opener_user, @opener_password)
    @cash_shift.update!(status: 'closed', closed_at: Time.current, closed_by: @opener_user)

    reference_date = Date.current
    create_bcv_rates!(date: reference_date)

    scraper_result = {
      status: :updated,
      fecha_referencia: reference_date
    }

    assert_difference('CashShift.where(status: "open").count', 1) do
      with_bcv_scraper_result(scraper_result) do
        post cash_shifts_path, as: :json
      end
    end

    assert_response :success

    payload = JSON.parse(response.body)
    assert payload.fetch('success')
    assert_equal 'updated', payload.fetch('scraper_status')
    assert_match(/Las tasas han sido actualizadas/i, payload.fetch('message'))

    opened_shift = CashShift.where(status: 'open').order(:id).last
    assert_equal @opener_user.id, opened_shift.opened_by_id
    assert_equal ventas_path, payload.fetch('redirect_url')
    assert_equal opened_shift.id, payload.fetch('cash_shift_id')
    assert_equal cash_shift_path(opened_shift), payload.fetch('cash_shift_url')

    rates_snapshot = payload.fetch('rates_snapshot')
    bcv_rates = rates_snapshot.fetch('bcv_rates')
    assert_equal 2, bcv_rates.size
    assert_includes bcv_rates.map { |rate| rate.fetch('description') }, 'Dolar BCV'
    assert_includes bcv_rates.map { |rate| rate.fetch('description') }, 'Euro BCV'
    assert(bcv_rates.all? { |rate| rate.fetch('fecha_referencia').present? })
    assert rates_snapshot.key?('other_rates')
  end

  test 'create opens shift when scraper reports up_to_date' do
    login!(@opener_user, @opener_password)
    @cash_shift.update!(status: 'closed', closed_at: Time.current, closed_by: @opener_user)

    reference_date = Date.current
    create_bcv_rates!(date: reference_date)

    scraper_result = {
      status: :up_to_date,
      fecha_referencia: reference_date
    }

    assert_difference('CashShift.where(status: "open").count', 1) do
      with_bcv_scraper_result(scraper_result) do
        post cash_shifts_path, as: :json
      end
    end

    assert_response :success

    payload = JSON.parse(response.body)
    assert payload.fetch('success')
    assert_equal 'up_to_date', payload.fetch('scraper_status')
    assert_match(/Las tasas ya estan actualizadas/i, payload.fetch('message'))

    opened_shift = CashShift.where(status: 'open').order(:id).last
    assert_equal opened_shift.id, payload.fetch('cash_shift_id')
    assert_equal cash_shift_path(opened_shift), payload.fetch('cash_shift_url')

    rates_snapshot = payload.fetch('rates_snapshot')
    bcv_rates = rates_snapshot.fetch('bcv_rates')
    assert_equal 2, bcv_rates.size
    assert(bcv_rates.all? { |rate| rate.fetch('fecha_referencia').present? })
    assert rates_snapshot.key?('other_rates')
  end

  test 'create returns error when scraper fails to update rates' do
    login!(@opener_user, @opener_password)
    @cash_shift.update!(status: 'closed', closed_at: Time.current, closed_by: @opener_user)

    assert_no_difference('CashShift.count') do
      with_bcv_scraper_result(nil) do
        post cash_shifts_path, as: :json
      end
    end

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_match(/No se pudo actualizar correctamente alguna tasa BCV/i, payload.fetch('error'))
  end

  private

  def create_bcv_rates!(date:)
    TasaCambio.create!(description: 'Dolar BCV', valor: 40, fecha_referencia: date)
    TasaCambio.create!(description: 'Euro BCV', valor: 43, fecha_referencia: date)
  end

  def with_bcv_scraper_result(result)
    original_call = BcvScraperService.method(:call)
    BcvScraperService.define_singleton_method(:call) { result }
    yield
  ensure
    BcvScraperService.define_singleton_method(:call, original_call)
  end

  def create_manager_user!(business:, prefix:)
    password = 'ClaveSegura1!'
    user = User.create!(
      email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      username: "#{prefix}#{SecureRandom.hex(3)}",
      password: password,
      password_confirmation: password,
      business: business,
      admin: false,
      personal: true,
      authorization_level: 'manager',
      active: true,
      full_name: "Usuario #{prefix}"
    )

    [user, password]
  end

  def login!(user, password)
    post sessions_path, params: { login: user.email, password: password }
  end
end
