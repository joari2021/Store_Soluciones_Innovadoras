require 'test_helper'
require 'securerandom'

class AccountSettlementsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ['users']
  fixtures :users

  setup do
    @business = Business.create!(name: "Negocio Cierres #{SecureRandom.hex(4)}")

    @admin_password = 'ClaveSegura1!'
    user_attrs = {
      email: "admin-settlement-#{SecureRandom.hex(4)}@example.com",
      username: "adminset#{SecureRandom.hex(3)}",
      password: @admin_password,
      password_confirmation: @admin_password,
      business: @business,
      admin: true,
      personal: false,
      active: true,
      full_name: 'Admin Settlement'
    }
    user_attrs[:authorization_level] = 'admin' if User.column_names.include?('authorization_level')

    @admin_user = User.create!(user_attrs)

    @settlement_bank = @business.accounts.create!(
      name: 'Banco receptor cierre',
      account_type: 'bank_account',
      currency: 'VES',
      balance: 0,
      active: true,
      theme_color: 'sky',
      is_primary: true
    )

    @biopago_account = @business.accounts.create!(
      name: 'Biopago',
      account_type: 'biopago',
      currency: 'VES',
      balance: 0,
      active: true,
      theme_color: 'emerald',
      settlement_account: @settlement_bank
    )

    @settlement = @biopago_account.account_settlements.create!(
      total_amount: 120,
      movements_count: 3,
      closed_at: Time.current,
      period_start_at: 1.day.ago,
      period_end_at: Time.current,
      settlement_account: @settlement_bank
    )

    login!(@admin_user, @admin_password)
  end

  test 'procesa comision de cierre pendiente biopago aunque no haya saldo previo en cuenta' do
    assert_equal 0.to_d, @settlement_bank.balance.to_d

    patch account_account_settlement_path(@biopago_account, @settlement), params: {
      account_settlement: {
        credited_amount: '0',
        commission_amount: '10',
        settlement_date: Date.current.strftime('%d-%m-%Y')
      }
    }

    assert_redirected_to account_account_settlement_path(@biopago_account, @settlement)
    follow_redirect!
    assert_response :success

    @settlement.reload
    assert @settlement.processed?
    assert_equal BigDecimal('10.0'), @settlement.commission_amount.to_d

    commission_movement = @settlement_bank.account_movements
                                         .where(movement_kind: 'expense', payment_method: 'settlement')
                                         .order(:id)
                                         .last
    assert_not_nil commission_movement
    assert_equal BigDecimal('10.0'), commission_movement.amount.to_d

    @settlement_bank.reload
    assert_equal BigDecimal('-10.0'), @settlement_bank.balance.to_d
  end

  test 'anexa movimientos tardios al cierre pendiente segun rango y recalcula total' do
    period_start = Time.zone.local(2026, 11, 7, 8, 24, 0)
    period_end = Time.zone.local(2026, 11, 7, 18, 31, 0)

    @settlement.update_columns(
      total_amount: BigDecimal('200.0'),
      movements_count: 1,
      period_start_at: period_start,
      period_end_at: period_end,
      processed_at: nil,
      updated_at: Time.current,
    )

    existing_movement = @biopago_account.account_movements.create!(
      movement_kind: 'income',
      amount: 200,
      description: 'Ingreso venta #1 [VENTA:1]',
      occurred_at: Time.zone.local(2026, 11, 7, 10, 0, 0),
      account_settlement: @settlement,
    )

    late_movement = @biopago_account.account_movements.create!(
      movement_kind: 'income',
      amount: 10_000,
      description: 'Cobro de deuda [DEBT:123] [DP:456]',
      occurred_at: Time.zone.local(2026, 11, 7, 10, 39, 0),
      created_at: Time.zone.local(2026, 11, 12, 9, 0, 0),
      updated_at: Time.zone.local(2026, 11, 12, 9, 0, 0),
    )

    get account_account_settlement_path(@biopago_account, @settlement)
    assert_response :success

    late_movement.reload
    @settlement.reload
    existing_movement.reload

    assert_equal @settlement.id, late_movement.account_settlement_id
    assert_equal @settlement.id, existing_movement.account_settlement_id
    assert_equal 2, @settlement.movements_count
    assert_equal BigDecimal('10200.0'), @settlement.total_amount.to_d
  end

  private

  def login!(user, password)
    post sessions_path, params: { login: user.email, password: password }
  end
end
