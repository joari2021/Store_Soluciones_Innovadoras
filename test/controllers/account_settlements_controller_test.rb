require 'test_helper'
require 'securerandom'

class AccountSettlementsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ['users']
  fixtures :users

  setup do
    @business = Business.create!(name: "Negocio Cierres #{SecureRandom.hex(4)}")

    @admin_password = 'ClaveSegura1!'
    @admin_user = User.create!(
      email: "admin-settlement-#{SecureRandom.hex(4)}@example.com",
      username: "adminset#{SecureRandom.hex(3)}",
      password: @admin_password,
      password_confirmation: @admin_password,
      business: @business,
      admin: true,
      personal: false,
      authorization_level: 'admin',
      active: true,
      full_name: 'Admin Settlement'
    )

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

  private

  def login!(user, password)
    post sessions_path, params: { login: user.email, password: password }
  end
end
