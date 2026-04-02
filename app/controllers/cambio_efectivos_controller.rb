class CambioEfectivosController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :set_cambio_efectivo, only: %i[destroy]
  before_action :authorize_destroy!, only: %i[destroy]

  def index
    initialize_date_filters
    scope = current_business.cambio_efectivos.includes(:user, :cash_shift).order(occurred_at: :desc)
    @cambio_efectivos = apply_date_filters(scope)
  end

  def create
    payload = cambio_efectivo_params

    open_cash_shift = current_business.cash_shifts.open.first
    if open_cash_shift.blank?
      return render json: { error: "Debes abrir un turno antes de realizar el cambio de efectivo." },
                    status: :unprocessable_entity
    end

    efectivo_vendido = parse_decimal(payload[:efectivo_vendido], default: 0).round(2)
    monto_caja_operativa = parse_decimal(payload[:monto_caja_operativa], default: 0).round(2)
    monto_caja_deposito = parse_decimal(payload[:monto_caja_deposito], default: 0).round(2)
    monto_recibido = parse_decimal(payload[:monto_recibido], default: 0).round(2)
    recargo_percent = parse_decimal(payload[:recargo_percent], default: 0).round(2)
    payment_group = payload[:payment_group].to_s

    if efectivo_vendido <= 0
      return render json: { error: "Debes indicar el efectivo a vender." }, status: :unprocessable_entity
    end

    if monto_recibido <= 0
      return render json: { error: "Debes indicar el monto a cobrar." }, status: :unprocessable_entity
    end

    if (monto_caja_operativa + monto_caja_deposito - efectivo_vendido).abs > 0.01
      return render json: { error: "Los montos de caja no cuadran con el efectivo a vender." },
                    status: :unprocessable_entity
    end

    cash_box_account = current_business.accounts.find_by(
      account_type: "cash_box",
      cash_role: "cash_box",
      currency: "VES",
    )
    cash_deposit_account = current_business.accounts.find_by(
      account_type: "cash_box",
      cash_role: "cash_deposit",
      currency: "VES",
    )

    if cash_box_account.blank? || cash_deposit_account.blank?
      return render json: { error: "No se encontraron las cajas en Bs configuradas." },
                    status: :unprocessable_entity
    end

    if monto_caja_operativa > cash_box_account.balance.to_d
      return render json: { error: "El monto en caja operativa excede el disponible." },
                    status: :unprocessable_entity
    end

    if monto_caja_deposito > cash_deposit_account.balance.to_d
      return render json: { error: "El monto en caja deposito excede el disponible." },
                    status: :unprocessable_entity
    end

    allowed_payment_group = CambioEfectivo::PAYMENT_GROUPS.key?(payment_group)
    unless allowed_payment_group
      return render json: { error: "Metodo de pago no valido." }, status: :unprocessable_entity
    end

    payments = Array(payload[:payments])
    payment_rows = []
    total_paid = 0.to_d

    payments.each do |payment|
      amount = parse_decimal(payment[:amount], default: 0).round(2)
      next unless amount.positive?

      account = current_business.accounts.find_by(id: payment[:account_id])
      return render json: { error: "Cuenta de pago no encontrada." }, status: :unprocessable_entity if account.nil?

      if account.currency.to_s != "VES"
        return render json: { error: "Solo se permiten pagos en Bs para el cambio de efectivo." },
                      status: :unprocessable_entity
      end

      if payment_group == "bank"
        unless account.account_type == "bank_account"
          return render json: { error: "Solo se permiten cuentas bancarias para pago movil o transferencia." },
                        status: :unprocessable_entity
        end
      else
        unless %w[biopago pos].include?(account.account_type)
          return render json: { error: "Solo se permiten cuentas Biopago o Punto de venta." },
                        status: :unprocessable_entity
        end
      end

      method = payment[:method].to_s
      if account.account_type == "bank_account"
        unless %w[transfer mobile].include?(method)
          return render json: { error: "Selecciona transferencia o pago movil." }, status: :unprocessable_entity
        end

        reference = payment[:reference].to_s.strip
        unless reference.match?(/^\d{4}$/)
          return render json: { error: "La referencia debe tener 4 digitos." }, status: :unprocessable_entity
        end

        payment_date = parse_payment_date(payment[:payment_date])
        if payment_date.blank?
          return render json: { error: "Debes indicar la fecha del pago." }, status: :unprocessable_entity
        end
      else
        method = account.account_type == "pos" ? "pos" : "biopago"
      end

      payment_rows << {
        account: account,
        amount: amount,
        method: method,
        reference: payment[:reference].to_s.strip,
        payment_date: payment[:payment_date].to_s,
      }

      total_paid += amount
    end

    if payment_rows.empty?
      return render json: { error: "Debes registrar al menos un metodo de pago." }, status: :unprocessable_entity
    end

    if total_paid + 0.01 < monto_recibido
      return render json: { error: "El total cobrado no puede ser menor al monto a cobrar." },
                    status: :unprocessable_entity
    end

    payment_details = payment_rows.map do |row|
      {
        account_id: row[:account].id,
        account_name: row[:account].name,
        account_type: row[:account].account_type,
        amount: row[:amount].to_d.to_f,
        method: row[:method],
        reference: row[:reference],
        payment_date: row[:payment_date],
      }
    end

    cambio_efectivo = current_business.cambio_efectivos.new(
      user: Current.user,
      cash_shift: open_cash_shift,
      efectivo_vendido: efectivo_vendido,
      monto_caja_operativa: monto_caja_operativa,
      monto_caja_deposito: monto_caja_deposito,
      monto_recibido: monto_recibido,
      recargo_percent: recargo_percent,
      payment_group: payment_group,
      currency: "VES",
      payment_details: { payments: payment_details },
      occurred_at: Time.current,
    )

    begin
      CambioEfectivo.transaction do
        cambio_efectivo.save!

        if monto_caja_operativa.positive?
          cash_box_account.account_movements.create!(
            cambio_efectivo: cambio_efectivo,
            movement_kind: "expense",
            amount: monto_caja_operativa,
            description: "Retiro de caja por cambio de efectivo [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            occurred_at: Time.current,
          )
        end

        if monto_caja_deposito.positive?
          cash_deposit_account.account_movements.create!(
            cambio_efectivo: cambio_efectivo,
            movement_kind: "expense",
            amount: monto_caja_deposito,
            description: "Retiro de deposito por cambio de efectivo [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            occurred_at: Time.current,
          )
        end

        payment_rows.each do |row|
          movement_attrs = {
            cambio_efectivo: cambio_efectivo,
            movement_kind: "income",
            amount: row[:amount],
            description: "Ingreso por cambio de efectivo [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            occurred_at: Time.current,
          }

          if row[:account].account_type == "bank_account" && %w[transfer mobile].include?(row[:method])
            movement_attrs[:payment_method] = row[:method] == "mobile" ? "mobile_payment" : "transfer"
          end

          movement_attrs[:reference] = row[:reference].presence if row[:reference].present?

          row[:account].account_movements.create!(movement_attrs)
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    render json: {
      id: cambio_efectivo.id,
      message: "Cambio de efectivo registrado correctamente.",
    }, status: :created
  end

  def validate
    payload = cambio_efectivo_params

    open_cash_shift = current_business.cash_shifts.open.first
    if open_cash_shift.blank?
      return render json: { error: "Debes abrir un turno antes de realizar el cambio de efectivo." },
                    status: :unprocessable_entity
    end

    efectivo_vendido = parse_decimal(payload[:efectivo_vendido], default: 0).round(2)
    monto_caja_operativa = parse_decimal(payload[:monto_caja_operativa], default: 0).round(2)
    monto_caja_deposito = parse_decimal(payload[:monto_caja_deposito], default: 0).round(2)
    monto_recibido = parse_decimal(payload[:monto_recibido], default: 0).round(2)
    payment_group = payload[:payment_group].to_s

    if efectivo_vendido <= 0
      return render json: { error: "Debes indicar el efectivo a vender." }, status: :unprocessable_entity
    end

    if monto_recibido <= 0
      return render json: { error: "Debes indicar el monto a cobrar." }, status: :unprocessable_entity
    end

    if (monto_caja_operativa + monto_caja_deposito - efectivo_vendido).abs > 0.01
      return render json: { error: "Los montos de caja no cuadran con el efectivo a vender." },
                    status: :unprocessable_entity
    end

    cash_box_account = current_business.accounts.find_by(
      account_type: "cash_box",
      cash_role: "cash_box",
      currency: "VES",
    )
    cash_deposit_account = current_business.accounts.find_by(
      account_type: "cash_box",
      cash_role: "cash_deposit",
      currency: "VES",
    )

    if cash_box_account.blank? || cash_deposit_account.blank?
      return render json: { error: "No se encontraron las cajas en Bs configuradas." },
                    status: :unprocessable_entity
    end

    if monto_caja_operativa > cash_box_account.balance.to_d
      return render json: { error: "El monto en caja operativa excede el disponible." },
                    status: :unprocessable_entity
    end

    if monto_caja_deposito > cash_deposit_account.balance.to_d
      return render json: { error: "El monto en caja deposito excede el disponible." },
                    status: :unprocessable_entity
    end

    unless CambioEfectivo::PAYMENT_GROUPS.key?(payment_group)
      return render json: { error: "Metodo de pago no valido." }, status: :unprocessable_entity
    end

    render json: { success: true }
  end

  def destroy
    CambioEfectivo.transaction do
      AccountMovement.where(cambio_efectivo_id: @cambio_efectivo.id).find_each(&:destroy!)
      @cambio_efectivo.destroy!
    end

    redirect_to cambio_efectivos_path, notice: "Cambio de efectivo eliminado y movimientos revertidos."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to cambio_efectivos_path, alert: e.message.presence || "No se pudo eliminar el cambio de efectivo."
  end

  private

  def set_cambio_efectivo
    @cambio_efectivo = current_business.cambio_efectivos.find(params[:id])
  end

  def authorize_destroy!
    return if current_user_admin?

    return if current_user_manager? && @cambio_efectivo&.cash_shift&.open?

    deny_access("No tienes permisos para eliminar este cambio de efectivo.")
    return
  end

  def cambio_efectivo_params
    params.require(:cambio_efectivo).permit(
      :efectivo_vendido,
      :monto_caja_operativa,
      :monto_caja_deposito,
      :monto_recibido,
      :recargo_percent,
      :payment_group,
      payments: %i[account_id amount method reference payment_date],
    )
  end

  def parse_decimal(value, default: 0)
    return default.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(",", ".")
    BigDecimal(cleaned)
  rescue ArgumentError
    default.to_d
  end

  def parse_payment_date(raw_value)
    return nil if raw_value.blank?

    return raw_value if raw_value.is_a?(Date)

    return raw_value.to_date if raw_value.is_a?(Time) || raw_value.is_a?(DateTime)

    raw_value = raw_value.to_s.strip
    return Date.parse(raw_value) if raw_value.match?(/^\d{4}-\d{2}-\d{2}$/)

    return Date.strptime(raw_value, "%d-%m-%Y") if raw_value.match?(/^\d{2}-\d{2}-\d{4}$/)

    nil
  rescue ArgumentError
    nil
  end

  def initialize_date_filters
    @selected_fecha_desde = parse_filter_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_filter_date(params[:fecha_hasta])

    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    @selected_fecha_desde_value = normalized_filter_date_value(params[:fecha_desde], @selected_fecha_desde)
    @selected_fecha_hasta_value = normalized_filter_date_value(params[:fecha_hasta], @selected_fecha_hasta)
    @date_filters_applied = [
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip,
    ].any?(&:present?)
  end

  def apply_date_filters(scope)
    filtered_scope = scope

    if @selected_fecha_desde.present?
      filtered_scope = filtered_scope.where("occurred_at >= ?",
                                            @selected_fecha_desde.in_time_zone("America/Caracas").beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      filtered_scope = filtered_scope.where("occurred_at <= ?",
                                            @selected_fecha_hasta.in_time_zone("America/Caracas").end_of_day)
    end

    filtered_scope
  end

  def parse_filter_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr("/", "-"), "%d-%m-%Y") if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def normalized_filter_date_value(raw_value, parsed_value)
    return parsed_value.strftime("%d-%m-%Y") if parsed_value.present?

    raw_value.to_s.strip
  end
end
