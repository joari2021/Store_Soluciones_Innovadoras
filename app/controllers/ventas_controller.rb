class VentasController < ApplicationController
  before_action :require_business

  def index
    @productos = current_business
                 .productos
                 .with_attached_foto
                 .includes(:product_variations, :stock_lot_variations, :stock_lots)
                 .order(:descripcion)

    @accounts = current_business.accounts.where(active: true).order(:name)

    @products_payload = @productos.map do |producto|
      variation_rows = producto.stock_lot_variations.to_a
      variation_groups = variation_rows.group_by(&:product_variation_id)
      variation_totals = variation_groups.transform_values do |rows|
        rows.sum { |row| row.quantity_remaining.to_d }
      end

      total_units = variation_totals.values.sum
      total_units = producto.stock_lots.to_a.sum { |lot| lot.quantity_remaining.to_d } if total_units.zero?

      variations_payload = producto.product_variations.sort_by(&:id).map do |variation|
        available = variation_totals[variation.id].to_d
        available = total_units if available.zero? && variation_totals.empty? && producto.product_variations.size == 1

        {
          id: variation.id,
          name: variation.description.to_s,
          available: available.to_f
        }
      end

      {
        id: producto.id,
        name: producto.descripcion.to_s,
        price_usd: producto.precio_venta_usd.to_f,
        available_total: total_units.to_f,
        variations: variations_payload
      }
    end

    @products_payload_by_id = @products_payload.index_by { |row| row[:id] }

    tasa_dolar = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : nil
    unidad_vi = @unidad_VI.is_a?(Numeric) ? @unidad_VI.to_d : nil

    @services = Service.includes(:system_service).where(available: true).order('system_services.name ASC, services.description ASC')
    @services_payload = @services.map do |service|
      unit_price_usd = service.fixed? ? service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi) : nil

      {
        id: service.id,
        name: service.description.to_s,
        system_name: service.system_service&.name.to_s,
        price_usd: unit_price_usd&.to_f,
        price_on_request: service.to_agree?
      }
    end
    @services_payload_by_id = @services_payload.index_by { |row| row[:id] }

    @accounts_payload = @accounts.map do |account|
      {
        id: account.id,
        name: account.name,
        account_type: account.account_type,
        currency: account.currency,
        currency_symbol: account.currency_symbol,
        is_bank: account.account_type == 'bank_account',
        is_primary: account.is_primary
      }
    end
  end

  def historial
    @ventas = current_business
              .ventas
              .includes(:cliente)
              .order(created_at: :desc)
  end

  def show
    @venta = current_business
             .ventas
             .includes(:cliente, venta_items: %i[producto product_variation], venta_payments: :account)
             .find(params[:id])
  end

  def create
    payload = venta_params
    items = Array(payload[:items])
    payments = Array(payload[:payments])
    raw_change = payload[:change]
    change_entries = if raw_change.is_a?(Array)
                       raw_change
                     elsif raw_change.present?
                       [raw_change]
                     else
                       []
                     end

    if items.empty?
      return render json: { error: 'Agrega productos o servicios antes de cobrar.' },
                    status: :unprocessable_entity
    end

    vat_mode = payload[:vat_mode].to_s
    vat_mode = 'none' unless Venta::VAT_MODES.key?(vat_mode)
    vat_rate = parse_decimal(payload[:vat_rate], default: 0.16).round(2)
    tasa_dolar = parse_decimal(payload[:tasa_dolar], default: TasaCambio.latest_value('Dolar BCV')).round(2)
    base_currency = normalize_currency(payload[:base_currency], default: 'USD')
    base_currency = 'USD' unless Venta::BASE_CURRENCIES.key?(base_currency)

    venta = current_business.ventas.new(
      status: 'draft',
      vat_mode: vat_mode,
      vat_rate: vat_rate,
      tasa_dolar: tasa_dolar,
      base_currency: base_currency
    )

    if payload[:cliente_id].present?
      cliente = current_business.clientes.find_by(id: payload[:cliente_id])
      venta.cliente = cliente if cliente
    end

    items.each do |item|
      item_type = item[:item_type].to_s
      if item_type == 'service' || item[:service_id].present?
        service_id = item[:service_id]
        service = Service.includes(:system_service).find_by(id: service_id)
        next unless service

        quantity = parse_decimal(item[:quantity], default: 0)
        next unless quantity.positive?

        unit_price_usd = if service.to_agree?
                           parse_decimal(item[:unit_price_usd], default: 0)
                         else
                           service_unit_price_usd(service, tasa_dolar)
                         end

        if unit_price_usd.nil? || unit_price_usd.to_d <= 0
          message = service.to_agree? ? 'Debes indicar el precio acordado del servicio.' : 'No se pudo calcular el precio del servicio.'
          return render json: { error: message }, status: :unprocessable_entity
        end

        venta.venta_items.build(
          product_name: service.description.to_s,
          variation_name: service.system_service&.name.presence || 'Servicio',
          quantity: quantity,
          unit_price_usd: unit_price_usd
        )
        next
      end

      product_id = item[:product_id]
      product = current_business.productos.includes(:product_variations).find_by(id: product_id)
      next unless product

      quantity = parse_decimal(item[:quantity], default: 0)
      next unless quantity.positive?

      variation = (product.product_variations.find_by(id: item[:variation_id]) if item[:variation_id].present?)
      variation ||= product.product_variations.order(:id).first
      next unless variation

      unit_price = product.precio_venta_usd.to_d
      unit_price /= (1 + vat_rate) if vat_mode == 'included' && vat_rate.positive?

      venta.venta_items.build(
        producto: product,
        product_variation: variation,
        quantity: quantity,
        unit_price_usd: unit_price
      )
    end

    if venta.venta_items.empty?
      return render json: { error: 'No hay items validos en la venta.' }, status: :unprocessable_entity
    end

    venta.valid?

    payment_rows = []
    payments.each do |payment|
      raw_amount = parse_decimal(payment[:amount], default: 0)
      next unless raw_amount.positive?

      account = current_business.accounts.find_by(id: payment[:account_id])
      return render json: { error: 'Cuenta de pago no encontrada.' }, status: :unprocessable_entity if account.nil?

      currency = normalize_currency(payment[:currency], default: account&.currency || 'USD')
      amount_usd = convert_payment_to_usd(raw_amount, currency, tasa_dolar)
      if amount_usd.nil?
        return render json: { error: 'Tasa dolar no disponible para pagos en VES.' },
                      status: :unprocessable_entity
      end

      method = payment[:method].to_s
      return render json: { error: 'Selecciona el metodo de pago.' }, status: :unprocessable_entity if method.blank?

      reference = payment[:reference].to_s.strip
      if account.account_type == 'bank_account'
        unless %w[transfer mobile].include?(method)
          return render json: { error: 'Selecciona transferencia o pago movil para cuentas bancarias.' },
                        status: :unprocessable_entity
        end

        unless valid_reference?(reference)
          return render json: { error: 'La referencia debe tener 6 digitos.' }, status: :unprocessable_entity
        end
      end

      payment_rows << {
        account_id: account&.id,
        payment_method: method,
        amount_usd: amount_usd,
        amount_original: raw_amount,
        currency: currency,
        reference: reference.presence,
        payment_kind: 'in'
      }
    end

    change_rows = []
    change_entries.each do |change_entry|
      change_amount = parse_decimal(change_entry[:amount], default: 0)
      next unless change_amount.positive?

      change_account = current_business.accounts.find_by(id: change_entry[:account_id])
      if change_account.nil?
        return render json: { error: 'Cuenta para vuelto no encontrada.' },
                      status: :unprocessable_entity
      end

      change_currency = normalize_currency(change_entry[:currency], default: change_account&.currency || 'USD')
      change_usd = convert_payment_to_usd(change_amount, change_currency, tasa_dolar)
      if change_usd.nil?
        return render json: { error: 'Tasa dolar no disponible para vuelto en VES.' }, status: :unprocessable_entity
      end

      change_method = change_entry[:method].to_s
      change_method = default_method_for_account(change_account) if change_method.blank?

      change_reference = change_entry[:reference].to_s.strip
      if change_account.account_type == 'bank_account'
        unless %w[transfer mobile].include?(change_method)
          return render json: { error: 'Selecciona transferencia o pago movil para cuentas bancarias.' },
                        status: :unprocessable_entity
        end

        unless valid_reference?(change_reference)
          return render json: { error: 'La referencia del vuelto debe tener 6 digitos.' }, status: :unprocessable_entity
        end
      end

      change_rows << {
        account_id: change_account&.id,
        payment_method: change_method,
        amount_usd: change_usd,
        amount_original: change_amount,
        currency: change_currency,
        reference: change_reference.presence,
        payment_kind: 'out'
      }
    end

    comparison_currency = base_currency
    comparison_currency = 'USD' if comparison_currency == 'VES' && tasa_dolar.to_d <= 0
    total_due = total_due_in_currency(venta, comparison_currency, tasa_dolar)
    paid_total = 0.to_d

    payment_rows.each do |row|
      converted = convert_payment_to_currency(row[:amount_original], row[:currency], comparison_currency, tasa_dolar)
      if converted.nil?
        return render json: { error: 'Tasa dolar no disponible para convertir pagos.' },
                      status: :unprocessable_entity
      end
      paid_total += converted
    end

    tolerance = 0.01
    delta = (paid_total - total_due).round(2)

    if delta < -tolerance
      remaining = delta.abs.round(2)
      return render json: { error: "Falta por cancelar #{remaining} #{comparison_currency}." },
                    status: :unprocessable_entity
    end

    # Vuelto es opcional; no se valida contra el delta.

    payment_rows.each { |row| venta.venta_payments.build(row) }
    change_rows.each { |row| venta.venta_payments.build(row) }

    if payment_rows.empty?
      return render json: { error: 'Debes registrar al menos un metodo de pago.' }, status: :unprocessable_entity
    end

    venta.status = 'paid'

    begin
      Venta.transaction do
        venta.save!

        venta.venta_items.each do |item|
          item.producto&.consume_variation_stock!(
            variation_id: item.product_variation_id,
            quantity_units: item.quantity
          )
        end

        payment_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account

          movement_attrs = {
            movement_kind: 'income',
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, 'Ingreso'),
            occurred_at: Time.current
          }
          if account.account_type == 'bank_account' && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          account.account_movements.create!(movement_attrs)
        end

        change_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account

          movement_attrs = {
            movement_kind: 'expense',
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, 'Vuelto'),
            occurred_at: Time.current
          }
          if account.account_type == 'bank_account' && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          account.account_movements.create!(movement_attrs)

          next unless account.account_type == 'bank_account' && row[:payment_method] == 'mobile'

          commission_amount = (row[:amount_original].to_d * 0.003).round(2)
          next unless commission_amount.positive?

          commission_attrs = {
            movement_kind: 'expense',
            amount: commission_amount,
            description: build_movement_description(venta, row, 'Comision pago movil'),
            occurred_at: Time.current,
            payment_method: normalize_account_movement_method('mobile')
          }
          account.account_movements.create!(commission_attrs)
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    render json: {
      id: venta.id,
      total_usd: venta.total_usd,
      total_bs: venta.total_bs
    }, status: :created
  end

  private

  def venta_params
    params.require(:venta).permit(
      :vat_mode,
      :vat_rate,
      :tasa_dolar,
      :base_currency,
      :cliente_id,
      items: %i[item_type product_id service_id variation_id quantity unit_price_usd],
      payments: %i[method amount account_id currency reference],
      change: %i[method amount account_id currency reference]
    )
  end

  def service_unit_price_usd(service, tasa_dolar)
    return nil unless service

    service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: parse_decimal(@unidad_VI, default: 0))
  end

  def parse_decimal(value, default: 0)
    return default.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(',', '.')
    BigDecimal(cleaned)
  rescue ArgumentError
    default.to_d
  end

  def normalize_currency(value, default: 'USD')
    normalized = value.to_s.strip.upcase
    return default if normalized.blank?

    normalized
  end

  def convert_payment_to_usd(amount, currency, tasa_dolar)
    return amount.to_d.round(2) if %w[USD USDT].include?(currency)

    if currency == 'VES'
      rate = tasa_dolar.to_d
      return nil unless rate.positive?

      return (amount.to_d / rate).round(2)
    end

    amount.to_d.round(2)
  end

  def convert_payment_to_currency(amount, currency, target_currency, tasa_dolar)
    from_currency = normalize_currency(currency, default: target_currency)
    to_currency = normalize_currency(target_currency, default: 'USD')
    return amount.to_d.round(2) if from_currency == to_currency

    rate = tasa_dolar.to_d
    if from_currency == 'VES' && %w[USD USDT].include?(to_currency)
      return nil unless rate.positive?

      return (amount.to_d / rate).round(2)
    end

    if %w[USD USDT].include?(from_currency) && to_currency == 'VES'
      return nil unless rate.positive?

      return (amount.to_d * rate).round(2)
    end

    amount.to_d.round(2)
  end

  def total_due_in_currency(venta, currency, tasa_dolar)
    return venta.total_usd.to_d.round(2) unless currency == 'VES'

    rate = tasa_dolar.to_d
    return 0.to_d unless rate.positive?

    venta.base_total
  end

  def valid_reference?(value)
    value.to_s.match?(/\A\d{6}\z/)
  end

  def build_movement_description(venta, row, label)
    reference = row[:reference].to_s.strip
    if reference.present?
      "#{label} venta ##{venta.id} - Ref #{reference}"
    else
      "#{label} venta ##{venta.id}"
    end
  end

  def normalize_account_movement_method(method)
    return 'mobile_payment' if method.to_s == 'mobile'

    method.to_s
  end

  def default_method_for_account(account)
    return '' unless account

    case account.account_type
    when 'cash_box'
      'cash'
    when 'card'
      'card'
    when 'digital_wallet'
      'wallet'
    when 'crypto_wallet'
      'crypto'
    else
      ''
    end
  end
end
