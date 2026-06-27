class CambioEfectivosController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :ensure_can_manage_cash_exchange!, only: %i[create validate]
  before_action :set_cambio_efectivo, only: %i[destroy]
  before_action :authorize_destroy!, only: %i[destroy]

  def index
    initialize_date_filters
    scope = current_business.cambio_efectivos.includes(:user, :cash_shift).order(occurred_at: :desc)
    @cambio_efectivos = apply_date_filters(scope)
  end

  def create
    payload = cambio_efectivo_params
    delivery_option = normalize_delivery_option(payload[:delivery_option], payload[:delivery_target])
    delivery_target = delivery_target_from_option(delivery_option)

    open_cash_shift = current_business.cash_shifts.open.first
    if open_cash_shift.blank?
      return render json: { error: "Debes abrir un turno antes de registrar la pasarela de cambios." },
                    status: :unprocessable_entity
    end

    efectivo_vendido = parse_decimal(payload[:efectivo_vendido], default: 0).round(2)
    monto_caja_operativa = parse_decimal(payload[:monto_caja_operativa], default: 0).round(2)
    monto_caja_deposito = parse_decimal(payload[:monto_caja_deposito], default: 0).round(2)
    monto_recibido = parse_decimal(payload[:monto_recibido], default: 0).round(2)
    monto_cuenta_origen = parse_decimal(payload[:monto_cuenta_origen], default: 0).round(2)
    recargo_percent = parse_decimal(payload[:recargo_percent], default: 0).round(2)
    payment_group = payload[:payment_group].to_s

    if efectivo_vendido <= 0
      return render json: { error: "Debes indicar el efectivo a vender." }, status: :unprocessable_entity
    end

    if monto_recibido <= 0
      return render json: { error: "Debes indicar el monto a cobrar." }, status: :unprocessable_entity
    end

    if delivery_target == 'cash' && (monto_caja_operativa + monto_caja_deposito - efectivo_vendido).abs > 0.01
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
    primary_bank_account = current_business.accounts.find_by(
      account_type: "bank_account",
      currency: "VES",
      is_primary: true,
    )

    if delivery_target == 'cash'
      if cash_box_account.blank? || cash_deposit_account.blank?
        return render json: { error: "No se encontraron las cajas en Bs configuradas." },
                      status: :unprocessable_entity
      end
    else
      if primary_bank_account.blank?
        return render json: { error: "No existe una cuenta bancaria principal en Bs para enviar fondos." },
                      status: :unprocessable_entity
      end

      if (monto_cuenta_origen - efectivo_vendido).abs > 0.01
        return render json: { error: "El monto a enviar debe coincidir con el descuento en la cuenta origen." },
                      status: :unprocessable_entity
      end
    end

    allowed_payment_group = payment_group_allowed_for_delivery_target?(payment_group: payment_group,
                                                                      delivery_target: delivery_target)
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
        return render json: { error: "Solo se permiten pagos en Bs para la pasarela de cambios." },
                      status: :unprocessable_entity
      end

      unless payment_account_allowed?(account: account, payment_group: payment_group, delivery_target: delivery_target)
        return render json: { error: "La cuenta seleccionada no es valida para el metodo de pago elegido." },
                      status: :unprocessable_entity
      end

      method = payment_method_for_account(account: account, payment_group: payment_group, raw_method: payment[:method])
      if account.account_type == "bank_account" && payment_group == "bank"
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
        account_name: row[:account].name_with_cash_role,
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
      payment_details: {
        delivery_target: delivery_target,
        delivery_option: delivery_option,
        source_account_id: primary_bank_account&.id,
        source_account_name: primary_bank_account&.name_with_cash_role,
        source_amount: monto_cuenta_origen.to_d.to_f,
        payments: payment_details,
      },
      occurred_at: Time.current,
    )

    begin
      CambioEfectivo.transaction do
        cambio_efectivo.save!

        if delivery_target == 'cash' && monto_caja_operativa.positive?
          cash_box_account.account_movements.create!(
            cambio_efectivo: cambio_efectivo,
            movement_kind: "expense",
            amount: monto_caja_operativa,
            description: "Retiro de caja por pasarela de cambios [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            occurred_at: Time.current,
          )
        end

        if delivery_target == 'cash' && monto_caja_deposito.positive?
          cash_deposit_account.account_movements.create!(
            cambio_efectivo: cambio_efectivo,
            movement_kind: "expense",
            amount: monto_caja_deposito,
            description: "Retiro de deposito por pasarela de cambios [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            occurred_at: Time.current,
          )
        end

        if delivery_target == 'digital' && monto_cuenta_origen.positive? && primary_bank_account.present?
          source_payment_method = delivery_option == 'third_party_bancamiga' ? 'third_party_transfer' : 'mobile_payment'

          primary_bank_account.account_movements.create!(
            cambio_efectivo: cambio_efectivo,
            movement_kind: "expense",
            amount: monto_cuenta_origen,
            description: "Salida por pasarela de cambios [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
            payment_method: source_payment_method,
            occurred_at: Time.current,
          )

          if delivery_option_requires_mobile_commission?(delivery_option)
            commission_amount = (monto_cuenta_origen.to_d * 0.003).round(2)
            if commission_amount.positive?
              primary_bank_account.account_movements.create!(
                cambio_efectivo: cambio_efectivo,
                movement_kind: "expense",
                amount: commission_amount,
                description: "Comision pago movil pasarela [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
                payment_method: "mobile_payment",
                occurred_at: Time.current,
              )
            end
          end
        end

        payment_rows.each do |row|
          movement_attrs = {
            cambio_efectivo: cambio_efectivo,
            movement_kind: "income",
            amount: row[:amount],
            description: "Ingreso por pasarela de cambios [CAMBIO_EFECTIVO:#{cambio_efectivo.id}]",
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
      message: "Pasarela de cambios registrada correctamente.",
    }, status: :created
  end

  def validate
    payload = cambio_efectivo_params
    delivery_option = normalize_delivery_option(payload[:delivery_option], payload[:delivery_target])
    delivery_target = delivery_target_from_option(delivery_option)

    open_cash_shift = current_business.cash_shifts.open.first
    if open_cash_shift.blank?
      return render json: { error: "Debes abrir un turno antes de registrar la pasarela de cambios." },
                    status: :unprocessable_entity
    end

    efectivo_vendido = parse_decimal(payload[:efectivo_vendido], default: 0).round(2)
    monto_caja_operativa = parse_decimal(payload[:monto_caja_operativa], default: 0).round(2)
    monto_caja_deposito = parse_decimal(payload[:monto_caja_deposito], default: 0).round(2)
    monto_recibido = parse_decimal(payload[:monto_recibido], default: 0).round(2)
    monto_cuenta_origen = parse_decimal(payload[:monto_cuenta_origen], default: 0).round(2)
    payment_group = payload[:payment_group].to_s

    if efectivo_vendido <= 0
      return render json: { error: "Debes indicar el efectivo a vender." }, status: :unprocessable_entity
    end

    if monto_recibido <= 0
      return render json: { error: "Debes indicar el monto a cobrar." }, status: :unprocessable_entity
    end

    if delivery_target == 'cash' && (monto_caja_operativa + monto_caja_deposito - efectivo_vendido).abs > 0.01
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

    if delivery_target == 'cash'
      if cash_box_account.blank? || cash_deposit_account.blank?
        return render json: { error: "No se encontraron las cajas en Bs configuradas." },
                      status: :unprocessable_entity
      end
    else
      primary_bank_account = current_business.accounts.find_by(
        account_type: "bank_account",
        currency: "VES",
        is_primary: true,
      )

      if primary_bank_account.blank?
        return render json: { error: "No existe una cuenta bancaria principal en Bs para enviar fondos." },
                      status: :unprocessable_entity
      end

      if (monto_cuenta_origen - efectivo_vendido).abs > 0.01
        return render json: { error: "El monto a enviar debe coincidir con el descuento en la cuenta origen." },
                      status: :unprocessable_entity
      end
    end

    unless payment_group_allowed_for_delivery_target?(payment_group: payment_group, delivery_target: delivery_target)
      return render json: { error: "Metodo de pago no valido." }, status: :unprocessable_entity
    end

    render json: { success: true }
  end

  def destroy
    CambioEfectivo.transaction do
      AccountMovement.where(cambio_efectivo_id: @cambio_efectivo.id).find_each(&:destroy!)
      @cambio_efectivo.destroy!
    end

    redirect_to historial_ventas_path, notice: "Operacion de pasarela eliminada y movimientos revertidos."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to historial_ventas_path, alert: e.message.presence || "No se pudo eliminar la operacion de pasarela."
  end

  private

  def set_cambio_efectivo
    @cambio_efectivo = current_business.cambio_efectivos.find(params[:id])
  end

  def authorize_destroy!
    return if current_user_admin?

    return if @cambio_efectivo&.cash_shift&.open? && @cambio_efectivo.user_id == Current.user&.id

    deny_access("No tienes permisos para eliminar esta operacion de pasarela.")
    return
  end

  def ensure_can_manage_cash_exchange!
    unless current_user_admin? || current_user_manager?
      return render json: { error: "Solo encargado o administrador pueden usar la pasarela de cambios." }, status: :forbidden
    end

    open_cash_shift = current_business.cash_shifts.open.includes(:active_cashier).first
    return if open_cash_shift.blank?

    active_cashier = open_cash_shift.active_cashier
    return if active_cashier.blank?
    return if active_cashier.id == Current.user&.id

    active_cashier_role = active_cashier.role_label.to_s.strip
    active_cashier_name = active_cashier.display_name.to_s.strip
    active_cashier_label = [active_cashier_role, active_cashier_name].reject(&:blank?).join(' ')

    render json: {
      error: "Los cambios solo pueden ser procesados por #{active_cashier_label}, quien es el cajero en este momento.",
      active_cashier: {
        id: active_cashier.id,
        name: active_cashier_name,
        role_label: active_cashier_role,
      }
    }, status: :forbidden
  end

  def cambio_efectivo_params
    params.require(:cambio_efectivo).permit(
      :efectivo_vendido,
      :monto_caja_operativa,
      :monto_caja_deposito,
      :monto_cuenta_origen,
      :monto_recibido,
      :recargo_percent,
      :delivery_target,
      :delivery_option,
      :payment_group,
      payments: %i[account_id amount method reference payment_date],
    )
  end

  def normalize_delivery_option(raw_option, fallback_target = nil)
    value = raw_option.to_s
    return 'cash' if value == 'cash'
    return 'mobile_other_banks' if value == 'mobile_other_banks'
    return 'third_party_bancamiga' if value == 'third_party_bancamiga'

    fallback = fallback_target.to_s
    return 'mobile_other_banks' if fallback == 'digital'

    'cash'
  end

  def delivery_target_from_option(delivery_option)
    delivery_option == 'cash' ? 'cash' : 'digital'
  end

  def delivery_option_requires_mobile_commission?(delivery_option)
    delivery_option == 'mobile_other_banks'
  end

  def payment_group_allowed_for_delivery_target?(payment_group:, delivery_target:)
    return %w[bank pos_biopago].include?(payment_group) if delivery_target == 'cash'

    %w[cash pos_biopago].include?(payment_group)
  end

  def payment_account_allowed?(account:, payment_group:, delivery_target:)
    account_type = account.account_type.to_s

    if delivery_target == 'cash'
      return account_type == 'bank_account' if payment_group == 'bank'

      return %w[biopago pos].include?(account_type)
    end

    return account_type == 'cash_box' if payment_group == 'cash'

    %w[biopago pos].include?(account_type)
  end

  def payment_method_for_account(account:, payment_group:, raw_method:)
    account_type = account.account_type.to_s

    return raw_method.to_s if account_type == 'bank_account' && payment_group == 'bank'
    return 'cash' if account_type == 'cash_box'
    return 'pos' if account_type == 'pos'
    return 'biopago' if account_type == 'biopago'

    raw_method.to_s
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
