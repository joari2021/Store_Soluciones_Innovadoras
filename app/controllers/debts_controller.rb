class DebtsController < ApplicationController
  before_action :require_business
  before_action :set_debt, only: %i[show edit update destroy]
  before_action :load_parties, only: %i[new create edit update]
  before_action :load_accounts, only: %i[new create edit update]

  def index
    @debts = current_business
             .debts
             .includes(:cliente, :supplier, :loan_account, :debt_payments)
             .order(Arel.sql('CASE WHEN due_on IS NULL THEN 1 ELSE 0 END'), :due_on, created_at: :desc)

    @receivable_count = @debts.count(&:receivable?)
    @payable_count = @debts.count(&:payable?)
    @overdue_count = @debts.count(&:overdue?)
    @next_due_on = @debts.map(&:due_on).compact.min
  end

  def new
    @debt = current_business.debts.new(
      debt_kind: 'receivable',
      issued_on: Date.current
    )
  end

  def create
    @debt = current_business.debts.new(debt_params)

    if register_payment_now?
      success = false
      Debt.transaction do
        @debt.save!
        success = record_initial_payment(@debt)
        raise ActiveRecord::Rollback unless success
      end

      if success
        redirect_to debts_path, notice: 'Deuda creada exitosamente.'
      else
        render :new, status: :unprocessable_entity
      end
      return
    end

    if @debt.save
      redirect_to debts_path, notice: 'Deuda creada exitosamente.'
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @payments = @debt.debt_payments.includes(:account).order(occurred_at: :desc)
  end

  def edit
  end

  def update
    @debt.assign_attributes(debt_params)

    if @debt.save
      redirect_to debts_path, notice: 'Deuda actualizada exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @debt.destroy
    redirect_to debts_path, notice: 'Deuda eliminada.'
  end

  def create_cliente
    cliente = current_business.clientes.new(quick_cliente_params)
    cliente.document_type = 'V' if cliente.document_type.blank?

    if cliente.phone.blank?
      render json: { error: 'El telefono es obligatorio.' }, status: :unprocessable_entity
      return
    end

    if cliente.save
      render json: {
        id: cliente.id,
        name: cliente.name,
        document: cliente.document_label,
        phone: cliente.phone
      }, status: :created
    else
      render json: { error: cliente.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def set_debt
    @debt = current_business.debts.find(params[:id])
  end

  def load_parties
    @clientes = current_business.clientes.order(:name)
    @suppliers = current_business.suppliers.order(:nombre)
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:name)
  end

  def debt_params
    params.require(:debt).permit(
      :name,
      :description,
      :reference,
      :debt_kind,
      :origin_kind,
      :amount,
      :currency,
      :issued_on,
      :due_on,
      :cliente_id,
      :supplier_id,
      :loan_account_id
    )
  end

  def register_payment_now?
    params[:register_payment].to_s == '1'
  end

  def payment_params
    params.permit(:payment_account_id, :payment_currency, :payment_amount, :payment_method, :payment_reference,
                  :payment_occurred_on)
  end

  def record_initial_payment(debt)
    account = current_business.accounts.find_by(id: payment_params[:payment_account_id])
    payment_currency = payment_params[:payment_currency].presence || account&.currency
    amount = parse_decimal(payment_params[:payment_amount])

    if account.nil? || amount <= 0 || payment_currency.blank?
      debt.errors.add(:base, 'Completa el pago inicial para registrarlo.')
      return false
    end

    if account.currency != payment_currency
      debt.errors.add(:base, 'La cuenta debe coincidir con la moneda seleccionada para el pago.')
      return false
    end

    if account.account_type == 'bank_account' && payment_params[:payment_method].blank?
      debt.errors.add(:base, 'Selecciona el metodo de pago para cuentas bancarias.')
      return false
    end

    payment_method = payment_params[:payment_method].presence
    reference = payment_params[:payment_reference].presence
    occurred_on = parse_payment_date(payment_params[:payment_occurred_on]) || Date.current

    payment = debt.debt_payments.new(
      account: account,
      amount: amount,
      currency: payment_currency,
      payment_method: payment_method,
      reference: reference,
      occurred_at: occurred_on
    )

    unless payment.valid?
      payment.errors.full_messages.each { |message| debt.errors.add(:base, message) }
      return false
    end

    if payment.amount_in_debt_currency > debt.balance
      debt.errors.add(:base, 'El pago inicial excede el saldo pendiente de la deuda.')
      return false
    end

    payment.save!
    create_account_movement(account, debt, amount, payment_method, reference, occurred_on)
    true
  rescue ActiveRecord::RecordInvalid => e
    debt.errors.add(:base, e.message)
    false
  end

  def create_account_movement(account, debt, amount, method, reference, occurred_on)
    movement_attrs = {
      movement_kind: debt.receivable? ? 'income' : 'expense',
      amount: amount,
      description: build_movement_description(debt, reference),
      occurred_at: occurred_on
    }

    if account.account_type == 'bank_account' && method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(method)
    end

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description(debt, reference)
    action = debt.receivable? ? 'Cobro deuda' : 'Pago deuda'
    base = "#{action} #{debt.name}"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
  end

  def normalize_account_movement_method(method)
    return 'mobile_payment' if method.to_s == 'mobile'

    method.to_s
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(',', '.')
    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_payment_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, '%d-%m-%Y')
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def quick_cliente_params
    params.require(:cliente).permit(:name, :phone, :address, :document_type, :document_number)
  end
end
