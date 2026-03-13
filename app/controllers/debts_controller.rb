class DebtsController < ApplicationController
  before_action :require_business
  before_action :set_debt, only: %i[show edit update destroy]
  before_action :load_parties, only: %i[new create edit update]
  before_action :load_accounts, only: %i[new create edit update]
  before_action :load_currency_rates, only: %i[new create]

  def index
    @debts = current_business
      .debts
      .includes(:cliente, :debt_payments)
      .order(Arel.sql("CASE WHEN due_on IS NULL THEN 1 ELSE 0 END"), :due_on, created_at: :desc)

    @receivable_count = @debts.count(&:receivable?)
    @payable_count = @debts.count(&:payable?)
    @overdue_count = @debts.count(&:overdue?)
    @next_due_on = @debts.map(&:due_on).compact.min
  end

  def new
    @debt = current_business.debts.new(
      debt_kind: "receivable",
      issued_on: Date.current,
    )
    @debt_entries_form = [default_debt_entry]
  end

  def create
    @debt_entries_form = debt_entries_form_params
    normalized_entries = normalized_debt_entries
    shared_attrs = shared_debt_params

    if normalized_entries.empty?
      @debt = current_business.debts.new(shared_attrs)
      @debt.errors.add(:base, "Debes agregar al menos una deuda con monto, moneda y fecha de emision.")
      render :new, status: :unprocessable_entity
      return
    end

    debts_to_create = normalized_entries.each_with_index.map do |entry, index|
      current_business.debts.new(
        shared_attrs.merge(entry).merge(
          name: debt_name_for_entry(index, entry[:description]),
        )
      )
    end

    @debt = debts_to_create.first

    invalid_rows = false
    debts_to_create.each_with_index do |debt, index|
      next if debt.valid?

      invalid_rows = true
      debt.errors.full_messages.each do |message|
        @debt.errors.add(:base, "Deuda #{index + 1}: #{message}")
      end
    end

    if invalid_rows
      render :new, status: :unprocessable_entity
      return
    end

    success = false
    Debt.transaction do
      debts_to_create.each(&:save!)

      if register_payment_now?
        success = record_initial_payments(debts_to_create)
        raise ActiveRecord::Rollback unless success
      else
        success = true
      end
    end

    if success
      notice = debts_to_create.size == 1 ? "Deuda creada exitosamente." : "#{debts_to_create.size} deudas creadas exitosamente."
      redirect_to debts_path, notice: notice
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
      redirect_to debts_path, notice: "Deuda actualizada exitosamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @debt.destroy
    redirect_to debts_path, notice: "Deuda eliminada."
  end

  def create_cliente
    cliente = current_business.clientes.new(quick_cliente_params)
    cliente.document_type = "V" if cliente.document_type.blank?

    if cliente.phone.blank?
      render json: { error: "El telefono es obligatorio." }, status: :unprocessable_entity
      return
    end

    if cliente.save
      render json: {
        id: cliente.id,
        name: cliente.name,
        document: cliente.document_label,
        phone: cliente.phone,
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
  end

  def load_accounts
    @accounts = current_business.accounts.where(active: true).order(:name)
  end

  def load_currency_rates
    @currency_rates_to_ves = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency).to_d.to_f
    end
    @currency_rates_to_ves["VES"] = 1.0
  end

  def debt_params
    params.require(:debt).permit(
      :name,
      :description,
      :debt_kind,
      :amount,
      :currency,
      :issued_on,
      :due_on,
      :cliente_id
    )
  end

  def shared_debt_params
    params.require(:debt).permit(
      :debt_kind,
      :cliente_id,
    )
  end

  def debt_entries_form_params
    rows = raw_debt_entry_rows.map do |row|
      next if row.blank?

      amount = row_value(row, :amount)
      currency = row_value(row, :currency)
      issued_on = row_value(row, :issued_on)
      due_on = row_value(row, :due_on)
      description = row_value(row, :description)
      next if [amount, currency, issued_on, due_on].all?(&:blank?)

      {
        amount: amount,
        currency: currency,
        issued_on: issued_on,
        due_on: due_on,
        description: description,
      }
    end.compact

    return [default_debt_entry] if rows.empty?

    rows
  end

  def normalized_debt_entries
    debt_entries_form_params.map do |row|
      {
        amount: parse_decimal(row[:amount]),
        currency: row[:currency].to_s.strip.upcase,
        issued_on: parse_debt_date(row[:issued_on]),
        due_on: parse_debt_date(row[:due_on]),
        description: row[:description].to_s.strip.presence,
      }
    end
  end

  def raw_debt_entry_rows
    raw = params[:debt_entries]

    rows = case raw
      when ActionController::Parameters
        raw.to_unsafe_h.sort_by { |key, _| key.to_i }.map { |_, value| value }
      when Hash
        raw.sort_by { |key, _| key.to_i }.map { |_, value| value }
      when Array
        raw
      else
        []
      end

    return rows if rows.present?

    legacy_row = {
      amount: params.dig(:debt, :amount),
      currency: params.dig(:debt, :currency),
      issued_on: params.dig(:debt, :issued_on),
      due_on: params.dig(:debt, :due_on),
      description: params.dig(:debt, :description),
    }

    if legacy_row.values.any?(&:present?)
      [legacy_row]
    else
      []
    end
  end

  def row_value(row, key)
    return "" if row.blank?

    row_hash = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
    row_hash[key].presence || row_hash[key.to_s].presence || ""
  end

  def default_debt_entry
    {
      amount: "0",
      currency: "USD",
      issued_on: Date.current.strftime("%d-%m-%Y"),
      due_on: "",
      description: "",
    }
  end

  def debt_name_for_entry(index, description)
    return description.to_s.strip.first(80) if description.present?

    "Deuda #{index + 1}"
  end

  def register_payment_now?
    params[:register_payment].to_s == "1"
  end

  def payment_params
    params.permit(:payment_account_id, :payment_currency, :payment_amount, :payment_method, :payment_reference,
                  :payment_occurred_on)
  end

  def record_initial_payments(debts)
    account = current_business.accounts.find_by(id: payment_params[:payment_account_id])
    payment_currency = payment_params[:payment_currency].presence || account&.currency
    amount = parse_decimal(payment_params[:payment_amount])

    if account.nil? || amount <= 0 || payment_currency.blank?
      @debt.errors.add(:base, "Completa el pago inicial para registrarlo.")
      return false
    end

    if account.currency != payment_currency
      @debt.errors.add(:base, "La cuenta debe coincidir con la moneda seleccionada para el pago.")
      return false
    end

    if account.account_type == "bank_account" && payment_params[:payment_method].blank?
      @debt.errors.add(:base, "Selecciona el metodo de pago para cuentas bancarias.")
      return false
    end

    payment_method = payment_params[:payment_method].presence
    reference = payment_params[:payment_reference].presence
    occurred_on = parse_payment_date(payment_params[:payment_occurred_on]) || Date.current
    total_pending = total_balance_in_payment_currency(debts, payment_currency)

    if total_pending <= 0
      @debt.errors.add(:base, "No hay saldo pendiente para aplicar el pago inicial.")
      return false
    end

    if amount > (total_pending + 0.01.to_d)
      @debt.errors.add(:base, "El pago inicial excede el saldo pendiente total de las deudas creadas.")
      return false
    end

    remaining_amount = amount.to_d.round(2)
    payments_to_persist = []

    debts.each do |debt|
      break if remaining_amount <= 0

      max_for_debt = max_payment_amount_for_debt(debt, payment_currency)
      next if max_for_debt <= 0

      allocation = [remaining_amount, max_for_debt].min.to_d.round(2)
      next if allocation <= 0

      payment = debt.debt_payments.new(
        account: account,
        amount: allocation,
        currency: payment_currency,
        payment_method: payment_method,
        reference: reference,
        occurred_at: occurred_on,
      )

      unless payment.valid?
        payment.errors.full_messages.each { |message| @debt.errors.add(:base, message) }
        return false
      end

      if payment.amount_in_debt_currency > debt.balance
        @debt.errors.add(:base, "No se pudo distribuir el pago inicial sin exceder el saldo de una deuda.")
        return false
      end

      payments_to_persist << [debt, payment]
      remaining_amount = (remaining_amount - payment.amount.to_d).round(2)
    end

    if payments_to_persist.empty?
      @debt.errors.add(:base, "No se pudo aplicar el pago inicial a las deudas cargadas.")
      return false
    end

    payments_to_persist.each do |debt, payment|
      payment.save!
      create_account_movement(account, debt, payment.amount, payment_method, reference, occurred_on)
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @debt.errors.add(:base, e.message)
    false
  end

  def total_balance_in_payment_currency(debts, payment_currency)
    debts.sum do |debt|
      conversion = CurrencyConverter.convert(
        amount: debt.balance,
        from_currency: debt.currency,
        to_currency: payment_currency,
      )
      conversion&.dig(:amount).to_d
    end
  end

  def max_payment_amount_for_debt(debt, payment_currency)
    conversion = CurrencyConverter.convert(
      amount: debt.balance,
      from_currency: debt.currency,
      to_currency: payment_currency,
    )
    return 0.to_d if conversion.blank?

    max_amount = conversion[:amount].to_d

    3.times do
      back_conversion = CurrencyConverter.convert(
        amount: max_amount,
        from_currency: payment_currency,
        to_currency: debt.currency,
      )

      if back_conversion.present? && back_conversion[:amount].to_d <= debt.balance.to_d
        return max_amount
      end

      max_amount = (max_amount - 0.01.to_d).round(2)
      break if max_amount <= 0
    end

    max_amount.positive? ? max_amount : 0.to_d
  end

  def create_account_movement(account, debt, amount, method, reference, occurred_on)
    movement_attrs = {
      movement_kind: debt.receivable? ? "income" : "expense",
      amount: amount,
      description: build_movement_description(debt, reference),
      occurred_at: occurred_on,
    }

    if account.account_type == "bank_account" && method.present?
      movement_attrs[:payment_method] = normalize_account_movement_method(method)
    end

    account.account_movements.create!(movement_attrs)
  end

  def build_movement_description(debt, reference)
    action = debt.receivable? ? "Cobro deuda" : "Pago deuda"
    base = "#{action} #{debt.name}"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
  end

  def normalize_account_movement_method(method)
    return "mobile_payment" if method.to_s == "mobile"

    method.to_s
  end

  def parse_decimal(value)
    return 0 if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(",", ".")
    BigDecimal(cleaned)
  rescue ArgumentError
    0
  end

  def parse_payment_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, "%d-%m-%Y")
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def parse_debt_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    Date.strptime(raw, "%d-%m-%Y")
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
