require 'test_helper'
require 'securerandom'

class DebtPaymentsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ['users']
  fixtures :users

  setup do
    @user = users(:jorge)
    @business = Business.create!(name: "Negocio Deudas #{SecureRandom.hex(4)}")

    @cliente = @business.clientes.create!(
      name: 'Cliente Cobro',
      document_type: 'V',
      document_number: "#{SecureRandom.random_number(10**8).to_s.rjust(8, '0')}"
    )

    @bank_account = @business.accounts.create!(
      name: 'Banco Cobros',
      account_type: 'bank_account',
      currency: 'VES',
      balance: 10_000,
      active: true,
      theme_color: 'sky',
      is_primary: true
    )

    @receivable_debt = @business.debts.create!(
      debt_kind: 'receivable',
      name: 'Cobro pendiente',
      cliente: @cliente,
      amount: 500,
      currency: 'VES',
      issued_on: Date.current,
      due_on: Date.current + 5.days,
      description: 'Cobro de prueba'
    )

    login_and_select_business!
  end

  test 'rejects duplicated bank receivable payment by account date and amount even with different method' do
    @receivable_debt.debt_payments.create!(
      account: @bank_account,
      amount: 120,
      occurred_at: Date.current,
      payment_method: 'transfer',
      reference: '123456'
    )

    assert_no_difference('DebtPayment.count') do
      post debt_debt_payments_path(@receivable_debt), params: {
        debt_payment: {
          account_id: @bank_account.id,
          amount: '120.00',
          occurred_at: Date.current.iso8601,
          payment_method: 'mobile',
          reference: '654321',
          notes: 'Intento duplicado'
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'Ya existe un pago registrado en Banco Cobros con monto 120.0 VES'
  end

  test 'overpayment submission creates one real bank movement amount' do
    payment_date = Date.current

    assert_difference('DebtPayment.count', 1) do
      assert_difference -> { @bank_account.account_movements.count }, 1 do
        post debt_debt_payments_path(@receivable_debt), params: {
          debt_payment: {
            account_id: @bank_account.id,
            amount: '6000.00',
            occurred_at: payment_date.iso8601,
            payment_method: 'transfer',
            reference: '111111',
            notes: 'Cobro con excedente',
            allow_overpayment: '1'
          }
        }
      end
    end

    assert_redirected_to debt_path(@receivable_debt)

    last_movement = @bank_account.account_movements.order(:created_at).last
    assert_equal BigDecimal('6000.0'), last_movement.amount.to_d

    debt_payments = @receivable_debt.debt_payments.order(:created_at).to_a
    assert debt_payments.size >= 1
  end

  test 'duplicate validation uses the real movement amount after overpayment split' do
    payment_date = Date.current

    post debt_debt_payments_path(@receivable_debt), params: {
      debt_payment: {
        account_id: @bank_account.id,
        amount: '6000.00',
        occurred_at: payment_date.iso8601,
        payment_method: 'transfer',
        reference: '111111',
        notes: 'Cobro con excedente',
        allow_overpayment: '1'
      }
    }

    assert_redirected_to debt_path(@receivable_debt)

    assert_no_difference('DebtPayment.count') do
      post debt_debt_payments_path(@receivable_debt), params: {
        debt_payment: {
          account_id: @bank_account.id,
          amount: '6000.00',
          occurred_at: payment_date.iso8601,
          payment_method: 'mobile',
          reference: '222222',
          notes: 'Intento duplicado',
          allow_overpayment: '1'
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'Ya existe un pago registrado en Banco Cobros con monto 6000.0 VES'
  end

  private

  def login_and_select_business!
    post sessions_path, params: { login: @user.email, password: '215150603' }
    post select_business_path(@business)
  end
end
