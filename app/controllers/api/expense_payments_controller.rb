class Api::ExpensePaymentsController < ApplicationController
  before_action :require_business
  before_action :set_expense

  # POST /gastos/:id/convert_amount
  def convert_amount
    amount = params[:amount].to_d
    from_currency = params[:from_currency].to_s.upcase
    to_currency = params[:to_currency].to_s.upcase

    reference_date = parse_reference_date(params[:date])

    if requires_exact_rate?(from_currency: from_currency, to_currency: to_currency)
      return render json: { error: 'Fecha invalida' }, status: :unprocessable_entity if reference_date.blank?

      reference = CurrencyConverter.reference_for_currency(from_currency)
      tasa = TasaCambio.find_by(description: reference, fecha_referencia: reference_date)

      unless tasa.present?
        return render json: { error: "No hay tasa #{reference} registrada para esa fecha" }, status: :not_found
      end

      converted_amount = (amount * tasa.valor.to_d).round(2)

      return render json: {
        amount: converted_amount.to_f,
        rate: tasa.valor.to_d.to_f,
        rate_reference: reference,
        fecha_referencia: reference_date
      }, status: :ok
    end

    result = CurrencyConverter.convert(
      amount: amount,
      from_currency: from_currency,
      to_currency: to_currency,
      on_date: reference_date
    )

    if result
      render json: { amount: result[:amount].to_f, rate: result[:rate].to_f }, status: :ok
    else
      render json: { error: 'No se pudo convertir el monto' }, status: :unprocessable_entity
    end
  end

  private

  def set_expense
    expense_id = params[:expense_id].presence || params[:id].presence
    @expense = current_business.expenses.find(expense_id)
  end

  def parse_reference_date(raw_date)
    return nil if raw_date.blank?

    normalized = raw_date.to_s.strip
    return Date.strptime(normalized.tr('/', '-'), '%d-%m-%Y') if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})

    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def requires_exact_rate?(from_currency:, to_currency:)
    to_currency == 'VES' && %w[USD EUR].include?(from_currency)
  end
end
