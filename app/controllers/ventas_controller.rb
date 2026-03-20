class VentasController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :require_admin, only: %i[destroy]
  before_action :set_venta, only: %i[destroy]
  before_action :set_draft_venta, only: %i[show_draft update_draft destroy_draft]

  def index
    @productos = current_business
      .productos
      .with_attached_foto
      .includes(:categoria, :product_variations, :stock_lot_variations, :stock_lots)
      .order(:descripcion)

    @accounts = current_business.accounts.with_attached_payment_method_image.where(active: true).order(:name)
    @open_cash_shift = current_business.cash_shifts.open.includes(:opened_by).first

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
          available: available.to_f,
        }
      end

      {
        id: producto.id,
        name: producto.descripcion.to_s,
        price_usd: producto.precio_venta_usd.to_f,
        available_total: total_units.to_f,
        variations: variations_payload,
      }
    end

    @products_payload_by_id = @products_payload.index_by { |row| row[:id] }

    tasa_dolar = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : nil
    unidad_vi = @unidad_VI.is_a?(Numeric) ? @unidad_VI.to_d : nil
    effective_bcv_rate = tasa_dolar.to_d.positive? ? tasa_dolar.to_d : TasaCambio.latest_value("Dolar BCV").to_d

    @services = current_business
      .services
      .includes(
        :system_service,
        service_expense_structures: [
          :service_manager_expenses,
          :service_variable_expenses,
          { service_nested_expenses: :nested_service },
          { service_product_expenses: [:product_variation, { producto: :product_variations }] },
        ],
      )
      .where(available: true)
      .visible_for_user(Current.user)
      .order("system_services.name ASC, services.description ASC")
    @services_payload = @services.map do |service|
      unit_price_usd = service.fixed? ? service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi) : nil
      unit_cost_usd = if service.auto_cost_stock_discount?
          service.total_expense_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi, active_only: true)
        end
      currency_base_reference = service.currency_base_price.to_s.strip.presence || Service::DEFAULT_REFERENCE
      currency_base_reference = Service::DEFAULT_REFERENCE if currency_base_reference == Service::LEGACY_USD_REFERENCE

      reference_rate_bs = case currency_base_reference
        when Service::BOLIVAR_REFERENCE
          1.to_d
        when Service::DEFAULT_REFERENCE
          effective_bcv_rate
        else
          TasaCambio.latest_value(currency_base_reference).to_d
        end

      currency_symbol = TasaCambio.latest_symbol(currency_base_reference).presence ||
                        TasaCambio::DEFAULT_SYMBOLS[currency_base_reference] ||
                        (currency_base_reference == Service::BOLIVAR_REFERENCE ? "Bs" : "$")

      nested_to_agree_costs = []
      consumable_costs = []

      service.active_expense_structures_for_sales.each do |structure|
        structure_label = structure.description.to_s.strip.presence || "Sin estructura"

        structure.service_nested_expenses.each do |expense|
          nested_service = expense.nested_service
          next unless nested_service&.to_agree?

          reference_name = expense.currency_reference.to_s.strip.presence || "Bs"
          reference_rate_bs = if reference_name == "Bs"
              1.to_d
            else
              TasaCambio.latest_value(reference_name).to_d
            end

          nested_to_agree_costs << {
            expense_id: expense.id,
            structure_id: structure.id,
            structure_name: structure_label,
            nested_service_id: nested_service.id,
            nested_service_name: nested_service.description.to_s,
            reference_name: reference_name,
            reference_symbol: TasaCambio.latest_symbol(reference_name).presence ||
                              TasaCambio::DEFAULT_SYMBOLS[reference_name] ||
                              (reference_name == "Bs" ? "Bs" : "$"),
            reference_rate_bs: reference_rate_bs.positive? ? reference_rate_bs.to_f : nil,
            default_amount_reference: expense.amount_reference.to_d.to_f,
            quantity: expense.quantity.to_d.to_f,
          }
        end

        structure.service_product_expenses.each do |expense|
          product = expense.producto
          next unless product

          variation = expense.product_variation || product.product_variations.order(:id).first
          next unless variation

          consumable_costs << {
            expense_id: expense.id,
            structure_id: structure.id,
            structure_name: structure_label,
            product_id: product.id,
            product_name: product.descripcion.to_s,
            variation_id: variation.id,
            variation_name: variation.description.to_s,
            quantity: expense.quantity.to_d.to_f,
            unit_price_usd: product.precio_venta_usd.to_d.to_f,
          }
        end
      end

      {
        id: service.id,
        name: service.description.to_s,
        system_name: service.system_service&.name.to_s,
        price_usd: unit_price_usd&.to_f,
        price_on_request: service.to_agree?,
        pricing_mode: service.pricing_mode,
        auto_cost_stock_discount: service.auto_cost_stock_discount?,
        unit_cost_usd: unit_cost_usd&.to_f,
        currency_base_price: currency_base_reference,
        currency_symbol: currency_symbol,
        reference_rate_bs: reference_rate_bs.positive? ? reference_rate_bs.to_f : nil,
        nested_to_agree_costs: nested_to_agree_costs,
        consumable_costs: consumable_costs,
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
        is_bank: account.account_type == "bank_account",
        is_primary: account.is_primary,
        payment_method_image_url: (url_for(account.payment_method_image) if account.payment_method_image.attached?),
      }
    end

    @drafts_payload = drafts_payload
  end

  def drafts
    render json: { drafts: drafts_payload }
  end

  def products_snapshot
    render json: {
      products: products_payload_for_business,
      drafts: drafts_payload,
      generated_at: Time.current.to_i,
    }
  end

  def show_draft
    render json: {
      draft: draft_summary_payload(@draft_venta).merge(
        state: draft_state_payload(@draft_venta),
        client: draft_client_payload(@draft_venta),
      ),
      drafts: drafts_payload,
      products: products_payload_for_business,
    }
  end

  def save_draft
    persist_draft
  end

  def update_draft
    persist_draft(existing_draft: @draft_venta)
  end

  def destroy_draft
    Venta.transaction do
      restore_stock_for_sale!(@draft_venta)
      @draft_venta.destroy!
    end

    render json: {
      success: true,
      drafts: drafts_payload,
      products: products_payload_for_business,
    }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message.presence || "No se pudo eliminar el borrador." }, status: :unprocessable_entity
  end

  def historial
    @cash_shifts_for_filter = current_business.cash_shifts.order(opened_at: :desc).limit(80)

    filtered_scope = apply_historial_filters(current_business.ventas)

    @total_sales = filtered_scope.count
    @sales_with_client = filtered_scope.where.not(cliente_id: nil).count

    summary_sales = filtered_scope
      .select(:id, :created_at, :base_currency, :total_usd, :total_bs, :tasa_dolar)
      .to_a
    summary_reference_service = SaleCurrencyReferenceService.new(summary_sales)

    summary_totals = summary_reference_service.totals_by_sale_id.values
    @total_usd = summary_totals.sum { |row| row[:usd_total].to_d }.round(2)
    @total_ves = summary_totals.sum { |row| row[:ves_total].to_d }.round(2)

    ventas_scope = filtered_scope
      .includes(:cliente, :user, :venta_payments)
      .order(created_at: :desc)

    @pagy, @ventas = pagy_countless(ventas_scope, items: 24)
    load_sales_reference_data!(sales: @ventas)
    load_historial_invoice_statuses!(sales: @ventas)
  end

  def show
    @venta = current_business
      .ventas
      .includes(:cliente, :user, venta_items: %i[producto product_variation], venta_payments: :account)
      .find(params[:id])

    @sale_reference = SaleCurrencyReferenceService.new([@venta]).totals_by_sale_id[@venta.id] || {}
    load_sale_credit_context!
    @sale_item_masked_names = sale_item_masked_names_for_view(@venta)
  end

  def destroy
    Venta.transaction do
      restore_stock_for_sale!(@venta)
      delete_account_movements_for_sale!(@venta)
      delete_service_cost_debts_for_sale!(@venta)
      @venta.destroy!
    end

    redirect_to historial_ventas_path,
                notice: "Venta eliminada exitosamente junto con sus registros asociados."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to historial_ventas_path,
                alert: e.message.presence || "No se pudo eliminar la venta."
  end

  def create
    payload = venta_params
    draft_id = payload[:draft_id].presence
    source_draft = nil
    if draft_id
      source_draft = current_business.ventas.where(status: "draft").includes(:venta_items,
                                                                             :cliente).find_by(id: draft_id)
      unless source_draft
        return render json: { error: "No se encontro el borrador seleccionado." },
                      status: :unprocessable_entity
      end
    end

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
    credit_sale = normalize_credit_sale_payload(payload[:credit_sale])
    credit_sale_due_on = parse_payment_date(credit_sale[:due_on])
    service_cost_payment_entries = Array(payload[:service_cost_payments])
    if credit_sale[:due_on].present? && credit_sale_due_on.blank?
      return render json: { error: "La fecha de vencimiento del credito es invalida." },
                    status: :unprocessable_entity
    end

    if items.empty?
      return render json: { error: "Agrega productos o servicios antes de cobrar." },
                    status: :unprocessable_entity
    end

    open_cash_shift = current_business.cash_shifts.open.first
    if open_cash_shift.blank?
      return render json: { error: "Debes abrir un turno antes de facturar." },
                    status: :unprocessable_entity
    end

    vat_mode = payload[:vat_mode].to_s
    vat_mode = "none" unless Venta::VAT_MODES.key?(vat_mode)
    vat_rate = parse_decimal(payload[:vat_rate], default: 0.16).round(2)
    tasa_dolar = parse_decimal(payload[:tasa_dolar], default: TasaCambio.latest_value("Dolar BCV")).round(2)
    base_currency = normalize_currency(payload[:base_currency], default: "USD")
    base_currency = "USD" unless Venta::BASE_CURRENCIES.key?(base_currency)

    venta = current_business.ventas.new(
      status: "draft",
      vat_mode: vat_mode,
      vat_rate: vat_rate,
      tasa_dolar: tasa_dolar,
      base_currency: base_currency,
      cash_shift: open_cash_shift,
      user: Current.user,
    )

    if payload[:cliente_id].present?
      cliente = current_business.clientes.find_by(id: payload[:cliente_id])
      venta.cliente = cliente if cliente
    end

    service_item_rows = []

    items.each do |item|
      item_type = item[:item_type].to_s
      if item_type == "service" || item[:service_id].present?
        service_id = item[:service_id]
        service = current_business
          .services
          .includes(:system_service,
                    service_expense_structures: %i[service_product_expenses
                                                   service_nested_expenses])
          .find_by(id: service_id)
        next unless service

        quantity = parse_decimal(item[:quantity], default: 0)
        next unless quantity.positive?

        unit_price_usd = if service.to_agree?
            parse_decimal(item[:unit_price_usd], default: 0)
          else
            service_unit_price_usd(service, tasa_dolar)
          end

        if unit_price_usd.nil? || unit_price_usd.to_d <= 0
          message = service.to_agree? ? "Debes indicar el precio acordado del servicio." : "No se pudo calcular el precio del servicio."
          return render json: { error: message }, status: :unprocessable_entity
        end

        line_subtotal = (unit_price_usd.to_d * quantity.to_d).round(2)

        venta.venta_items.build(
          product_name: service.description.to_s,
          variation_name: service.system_service&.name.presence || "Servicio",
          quantity: quantity,
          unit_price_usd: unit_price_usd,
          subtotal_usd: line_subtotal,
        )

        service_item_rows << {
          service: service,
          quantity: quantity,
          payload: item.to_h,
        }
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
      unit_price /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive?
      line_subtotal = (unit_price.to_d * quantity.to_d).round(2)

      venta.venta_items.build(
        producto: product,
        product_variation: variation,
        quantity: quantity,
        unit_price_usd: unit_price,
        subtotal_usd: line_subtotal,
      )
    end

    if venta.venta_items.empty?
      return render json: { error: "No hay items validos en la venta." }, status: :unprocessable_entity
    end

    venta.valid?

    service_cost_obligations, service_cost_error = build_service_cost_obligations(
      service_item_rows: service_item_rows,
      tasa_dolar: tasa_dolar,
    )
    return render json: { error: service_cost_error }, status: :unprocessable_entity if service_cost_error.present?

    service_cost_settlements, service_cost_error = build_service_cost_settlements(
      obligations: service_cost_obligations,
      raw_rows: service_cost_payment_entries,
      tasa_dolar: tasa_dolar,
    )
    return render json: { error: service_cost_error }, status: :unprocessable_entity if service_cost_error.present?

    payment_rows = []
    bank_payment_keys_in_request = {}
    payments.each do |payment|
      raw_amount = parse_decimal(payment[:amount], default: 0)
      next unless raw_amount.positive?

      account = current_business.accounts.find_by(id: payment[:account_id])
      return render json: { error: "Cuenta de pago no encontrada." }, status: :unprocessable_entity if account.nil?

      currency = normalize_currency(payment[:currency], default: account&.currency || "USD")
      amount_usd = convert_payment_to_usd(raw_amount, currency, tasa_dolar)
      if amount_usd.nil?
        return render json: { error: "Tasa dolar no disponible para pagos en VES." },
                      status: :unprocessable_entity
      end

      method = payment[:method].to_s
      return render json: { error: "Selecciona el metodo de pago." }, status: :unprocessable_entity if method.blank?

      reference = payment[:reference].to_s.strip
      payment_date = parse_payment_date(payment[:payment_date])
      if account.account_type == "bank_account"
        unless %w[transfer mobile].include?(method)
          return render json: { error: "Selecciona transferencia o pago movil para cuentas bancarias." },
                        status: :unprocessable_entity
        end

        unless valid_reference?(reference)
          return render json: { error: "La referencia debe tener 6 digitos." }, status: :unprocessable_entity
        end

        if payment_date.blank?
          return render json: { error: "Debes indicar la fecha del pago para cuentas bancarias." },
                        status: :unprocessable_entity
        end

        amount_signature = raw_amount.to_d.round(2)
        duplicate_key = [account.id, payment_date.iso8601, amount_signature.to_s("F")].join("|")
        if bank_payment_keys_in_request.key?(duplicate_key)
          duplicate_info = duplicate_bank_payment_payload(
            account: account,
            payment_date: payment_date,
            amount_original: amount_signature,
            existing_payment: nil,
          )

          return render json: {
                          error: duplicate_info[:message],
                          duplicate_payment: duplicate_info.except(:message),
                        }, status: :unprocessable_entity
        end

        duplicated_payment = find_duplicate_bank_payment(
          account_id: account.id,
          payment_date: payment_date,
          amount_original: amount_signature,
        )

        if duplicated_payment.present?
          duplicate_info = duplicate_bank_payment_payload(
            account: account,
            payment_date: payment_date,
            amount_original: amount_signature,
            existing_payment: duplicated_payment,
          )

          return render json: {
                          error: duplicate_info[:message],
                          duplicate_payment: duplicate_info.except(:message),
                        }, status: :unprocessable_entity
        end

        bank_payment_keys_in_request[duplicate_key] = true
      end

      payment_rows << {
        account_id: account&.id,
        payment_method: method,
        amount_usd: amount_usd,
        amount_original: raw_amount,
        currency: currency,
        reference: reference.presence,
        payment_date: payment_date,
        payment_kind: "in",
      }
    end

    change_rows = []
    change_entries.each do |change_entry|
      change_amount = parse_decimal(change_entry[:amount], default: 0)
      next unless change_amount.positive?

      change_account = current_business.accounts.find_by(id: change_entry[:account_id])
      if change_account.nil?
        return render json: { error: "Cuenta para vuelto no encontrada." },
                      status: :unprocessable_entity
      end

      change_currency = normalize_currency(change_entry[:currency], default: change_account&.currency || "USD")
      change_usd = convert_payment_to_usd(change_amount, change_currency, tasa_dolar)
      if change_usd.nil?
        return render json: { error: "Tasa dolar no disponible para vuelto en VES." }, status: :unprocessable_entity
      end

      change_method = change_entry[:method].to_s
      change_method = default_method_for_account(change_account) if change_method.blank?

      change_reference = change_entry[:reference].to_s.strip
      if change_account.account_type == "bank_account"
        unless %w[transfer mobile].include?(change_method)
          return render json: { error: "Selecciona transferencia o pago movil para cuentas bancarias." },
                        status: :unprocessable_entity
        end

        unless valid_reference?(change_reference)
          return render json: { error: "La referencia del vuelto debe tener 6 digitos." }, status: :unprocessable_entity
        end
      end

      change_rows << {
        account_id: change_account&.id,
        payment_method: change_method,
        amount_usd: change_usd,
        amount_original: change_amount,
        currency: change_currency,
        reference: change_reference.presence,
        payment_kind: "out",
      }
    end

    comparison_currency = base_currency
    comparison_currency = "USD" if comparison_currency == "VES" && tasa_dolar.to_d <= 0
    total_due = total_due_in_currency(venta, comparison_currency, tasa_dolar)
    paid_total = 0.to_d

    payment_rows.each do |row|
      converted = convert_payment_to_currency(row[:amount_original], row[:currency], comparison_currency, tasa_dolar)
      if converted.nil?
        return render json: { error: "Tasa dolar no disponible para convertir pagos." },
                      status: :unprocessable_entity
      end
      paid_total += converted
    end

    tolerance = 0.01
    delta = (paid_total - total_due).round(2)

    remaining_credit_amount = delta < -tolerance ? delta.abs.round(2) : 0.to_d

    if remaining_credit_amount.positive? && !credit_sale[:enabled]
      return render json: { error: "Falta por cancelar #{remaining_credit_amount} #{comparison_currency}." },
                    status: :unprocessable_entity
    end

    if remaining_credit_amount.positive? && venta.cliente.blank?
      return render json: { error: "Debes seleccionar un cliente para registrar saldo en deuda por cobrar." },
                    status: :unprocessable_entity
    end

    # Vuelto es opcional; no se valida contra el delta.

    payment_rows.each { |row| venta.venta_payments.build(row) }
    change_rows.each { |row| venta.venta_payments.build(row) }

    if payment_rows.empty? && !remaining_credit_amount.positive?
      return render json: { error: "Debes registrar al menos un metodo de pago." }, status: :unprocessable_entity
    end

    venta.status = "paid"

    begin
      Venta.transaction do
        if source_draft
          restore_stock_for_sale!(source_draft)
          source_draft.destroy!
        end

        venta.save!

        reserve_product_stock_for_sale!(venta)
        reserved_service_products = reserve_service_product_expenses_for_items!(service_item_rows, venta: venta)
        notes_payload = parse_notes_payload(venta.notes)
        notes_payload.delete("draft_state")
        notes_payload["reserved_product_items"] = reserved_product_items_payload_for_sale(venta)
        notes_payload["reserved_service_products"] = reserved_service_products
        notes_payload["service_cost_settlements"] = service_cost_settlements_payload_for_notes(service_cost_settlements)
        venta.update!(notes: serialize_notes_payload(notes_payload))

        payment_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account

          movement_attrs = {
            movement_kind: "income",
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, "Ingreso"),
            occurred_at: Time.current,
          }
          if account.account_type == "bank_account" && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          account.account_movements.create!(movement_attrs)
        end

        change_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account

          movement_attrs = {
            movement_kind: "expense",
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, "Vuelto"),
            occurred_at: Time.current,
          }
          if account.account_type == "bank_account" && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          account.account_movements.create!(movement_attrs)

          next unless account.account_type == "bank_account" && row[:payment_method] == "mobile"

          commission_amount = (row[:amount_original].to_d * 0.003).round(2)
          next unless commission_amount.positive?

          commission_attrs = {
            movement_kind: "expense",
            amount: commission_amount,
            description: build_movement_description(venta, row, "Comision pago movil"),
            occurred_at: Time.current,
            payment_method: normalize_account_movement_method("mobile"),
          }
          account.account_movements.create!(commission_attrs)
        end

        register_service_cost_settlements_for_sale!(
          venta: venta,
          settlements: service_cost_settlements,
        )

        if remaining_credit_amount.positive?
          create_receivable_debt_for_sale!(
            venta: venta,
            amount: remaining_credit_amount,
            currency: comparison_currency,
            due_on: credit_sale_due_on,
          )
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    render json: {
      id: venta.id,
      total_usd: venta.total_usd,
      total_bs: venta.total_bs,
      drafts: drafts_payload,
      products: products_payload_for_business,
    }, status: :created
  end

  private

  def set_venta
    @venta = current_business
      .ventas
      .includes(venta_items: %i[producto product_variation])
      .find(params[:id])
  end

  def set_draft_venta
    @draft_venta = current_business
      .ventas
      .where(status: "draft")
      .includes(:cliente, :venta_items)
      .find(params[:id])
  end

  def sale_item_masked_names_for_view(venta)
    return {} if current_user_admin?

    service_items = venta.venta_items.select { |item| item.producto_id.blank? }
    return {} if service_items.empty?

    by_key, by_description = service_visibility_candidates_for_items(service_items)

    service_items.each_with_object({}) do |item, masked_names|
      candidates = service_visibility_candidates_for_item(
        item: item,
        by_key: by_key,
        by_description: by_description,
      )

      next if candidates.empty?
      next unless candidates.any? { |service| service.restricted_service? || service.caution_service? }

      masked_names[item.id] = "Servicio de internet"
    end
  end

  def service_visibility_candidates_for_items(service_items)
    descriptions = service_items.filter_map { |item| item.product_name.to_s.strip.presence }.uniq

    by_key = Hash.new { |hash, key| hash[key] = [] }
    by_description = Hash.new { |hash, key| hash[key] = [] }
    return [by_key, by_description] if descriptions.empty?

    services = current_business
      .services
      .includes(:system_service)
      .where(description: descriptions)

    services.each do |service|
      description_key = normalized_service_snapshot_value(service.description)
      next if description_key.blank?

      system_key = normalized_service_snapshot_value(service.system_service&.name)
      by_key[[description_key, system_key]] << service
      by_description[description_key] << service
    end

    [by_key, by_description]
  end

  def service_visibility_candidates_for_item(item:, by_key:, by_description:)
    description_key = normalized_service_snapshot_value(item.product_name)
    return [] if description_key.blank?

    system_key = normalized_service_snapshot_value(item.variation_name)
    exact_match = by_key[[description_key, system_key]]
    return exact_match if exact_match.present?

    fallback_matches = by_description[description_key]
    fallback_matches.size == 1 ? fallback_matches : []
  end

  def normalized_service_snapshot_value(value)
    value.to_s.strip.downcase.presence
  end

  def apply_historial_filters(scope)
    @cliente_query = params[:cliente_query].to_s.strip.presence
    @selected_cash_shift_id = params[:cash_shift_id].to_s.strip.presence
    @selected_fecha_desde = parse_historial_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_historial_date(params[:fecha_hasta])

    legacy_exact_date = parse_historial_date(params[:fecha])
    if legacy_exact_date.present? && @selected_fecha_desde.blank? && @selected_fecha_hasta.blank?
      @selected_fecha_desde = legacy_exact_date
      @selected_fecha_hasta = legacy_exact_date
    end

    filters_explicitly_present = [
      @cliente_query,
      @selected_cash_shift_id,
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip,
      params[:fecha].to_s.strip,
    ].any?(&:present?)

    filtered_scope = scope

    if @cliente_query.present?
      query_value = "%#{ActiveRecord::Base.sanitize_sql_like(@cliente_query)}%"
      filtered_scope = filtered_scope
        .joins(:cliente)
        .where(
          "clientes.name ILIKE :query OR clientes.document_number ILIKE :query OR clientes.document_type ILIKE :query",
          query: query_value,
        )
    end

    if @selected_cash_shift_id.present?
      filtered_scope = filtered_scope.where(cash_shift_id: @selected_cash_shift_id.to_i)
    end

    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    if @selected_fecha_desde.present?
      filtered_scope = filtered_scope.where("created_at >= ?", @selected_fecha_desde.in_time_zone.beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      filtered_scope = filtered_scope.where("created_at <= ?", @selected_fecha_hasta.in_time_zone.end_of_day)
    end

    @selected_fecha_desde = nil unless filters_explicitly_present || @selected_fecha_desde.present?
    @selected_fecha_hasta = nil unless filters_explicitly_present || @selected_fecha_hasta.present?

    @historial_query_params = build_historial_query_params
    filtered_scope
  end

  def parse_historial_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr("/", "-"), "%d-%m-%Y") if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})

    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def parse_payment_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr("/", "-"), "%d-%m-%Y") if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})

    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def find_duplicate_bank_payment(account_id:, payment_date:, amount_original:)
    return nil if account_id.blank? || payment_date.blank?

    normalized_amount = amount_original.to_d.round(2)
    return nil unless normalized_amount.positive?

    VentaPayment
      .joins(:venta)
      .where(
        account_id: account_id,
        payment_kind: "in",
        payment_date: payment_date,
        amount_original: normalized_amount,
      )
      .where(ventas: { business_id: current_business.id })
      .order("ventas.created_at DESC")
      .first
  end

  def duplicate_bank_payment_payload(account:, payment_date:, amount_original:, existing_payment: nil)
    venta_id = existing_payment&.venta_id
    venta_url = venta_id.present? ? venta_path(venta_id) : nil
    date_label = payment_date.strftime("%d/%m/%Y")
    normalized_amount = amount_original.to_d.round(2)

    {
      account_id: account.id,
      account_name: account.name,
      payment_date: date_label,
      amount: normalized_amount.to_s("F"),
      currency: account.currency,
      currency_symbol: account.currency_symbol,
      venta_id: venta_id,
      venta_url: venta_url,
      message: "Ya existe un pago registrado en #{account.name} con monto #{normalized_amount.to_s("F")} #{account.currency} para la fecha #{date_label}.",
    }
  end

  def build_historial_query_params
    {}.tap do |hash|
      hash[:cliente_query] = @cliente_query if @cliente_query.present?
      hash[:cash_shift_id] = @selected_cash_shift_id if @selected_cash_shift_id.present?
      hash[:fecha_desde] = format_historial_date(@selected_fecha_desde) if @selected_fecha_desde.present?
      hash[:fecha_hasta] = format_historial_date(@selected_fecha_hasta) if @selected_fecha_hasta.present?
    end
  end

  def format_historial_date(date)
    date.strftime("%d-%m-%Y")
  end

  def load_sales_reference_data!(sales:)
    reference_service = SaleCurrencyReferenceService.new(Array(sales))
    @sales_reference_by_id = reference_service.totals_by_sale_id
    @sales_reference_rates_by_date = reference_service.rates_by_date
  end

  def load_historial_invoice_statuses!(sales:)
    sale_ids = Array(sales).map(&:id).compact.uniq
    default_status = sale_credit_status_for(total: 0, paid: 0, balance: 0)

    sales_by_id = Array(sales).index_by(&:id)

    @invoice_statuses_by_sale_id = sale_ids.each_with_object({}) do |sale_id, hash|
      hash[sale_id] = default_status.dup
    end
    return if sale_ids.empty?

    sale_ids_pattern = sale_ids.join("|")
    linked_debts = current_business
      .debts
      .includes(:debt_payments)
      .where(debt_kind: "receivable")
      .where("description ~ ?", "\\[VENTA:(#{sale_ids_pattern})\\]")

    debts_by_sale_id = Hash.new { |hash, key| hash[key] = [] }

    linked_debts.each do |debt|
      match = debt.description.to_s.match(/\[VENTA:(\d+)\]/)
      next if match.blank?

      sale_id = match[1].to_i
      next unless @invoice_statuses_by_sale_id.key?(sale_id)

      debts_by_sale_id[sale_id] << debt
    end

    debts_by_sale_id.each do |sale_id, debts|
      total = debts.sum { |debt| debt.amount.to_d }
      paid = debts.sum { |debt| debt.paid_amount.to_d }
      balance = debts.sum { |debt| debt.balance.to_d }

      sale = sales_by_id[sale_id]
      has_payments = sale&.venta_payments&.any? { |payment| payment.payment_kind == "in" }

      @invoice_statuses_by_sale_id[sale_id] = sale_credit_status_for(
        total: total,
        paid: paid,
        balance: balance,
        has_payments: has_payments,
      )
    end
  end

  def restore_stock_for_sale!(venta)
    grouped_items = venta.venta_items
                         .select { |item| item.producto_id.present? && item.product_variation_id.present? }
                         .group_by { |item| [item.producto_id, item.product_variation_id] }

    grouped_items.each do |(producto_id, variation_id), items|
      quantity_units = items.sum { |item| item.quantity.to_d }
      next unless quantity_units.positive?

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
      )
    end

    restore_reserved_service_stock_from_notes!(venta)
  end

  def restore_product_variation_units!(producto_id:, variation_id:, quantity_units:, venta:)
    producto = current_business.productos.find_by(id: producto_id)
    return unless producto

    remaining_to_restore = quantity_units.to_d

    producto.stock_lots.ordered_fifo.each do |lot|
      row = lot.stock_lot_variations.find_by(product_variation_id: variation_id)
      next unless row

      current_remaining = row.quantity_remaining.to_d
      max_quantity = row.quantity_in.to_d
      available_capacity = max_quantity - current_remaining
      next unless available_capacity.positive?

      restored = [available_capacity, remaining_to_restore].min
      next unless restored.positive?

      row.update!(quantity_remaining: current_remaining + restored)
      lot.sync_quantity_remaining_from_variations!

      remaining_to_restore -= restored
      break if remaining_to_restore <= 0
    end

    return if remaining_to_restore <= 0

    raise ActiveRecord::RecordInvalid.new(venta),
          "No se pudo restaurar todo el stock de la venta ##{venta.id} (faltan #{remaining_to_restore.to_f.round(4)} unidades)."
  end

  def delete_account_movements_for_sale!(venta)
    pattern = "%[VENTA:#{venta.id}]%"

    AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where("account_movements.description LIKE ?", pattern)
      .find_each(&:destroy!)
  end

  def delete_service_cost_debts_for_sale!(venta)
    current_business
      .debts
      .where(venta_id: venta.id, service_cost_pending: true)
      .find_each(&:destroy!)
  end

  def persist_draft(existing_draft: nil)
    payload = venta_params
    items = Array(payload[:items])

    if items.empty?
      return render json: { error: "Agrega al menos un producto o servicio para guardar el borrador." },
                    status: :unprocessable_entity
    end

    vat_mode = payload[:vat_mode].to_s
    vat_mode = "none" unless Venta::VAT_MODES.key?(vat_mode)
    vat_rate = parse_decimal(payload[:vat_rate], default: 0.16).round(2)
    tasa_dolar = parse_decimal(payload[:tasa_dolar], default: TasaCambio.latest_value("Dolar BCV")).round(2)
    base_currency = normalize_currency(payload[:base_currency], default: "USD")
    base_currency = "USD" unless Venta::BASE_CURRENCIES.key?(base_currency)

    draft = existing_draft
    if draft.nil? && payload[:draft_id].present?
      draft = current_business.ventas.where(status: "draft").includes(:cliente,
                                                                      :venta_items).find_by(id: payload[:draft_id])
      unless draft
        return render json: { error: "No se encontro el borrador a actualizar." },
                      status: :unprocessable_entity
      end
    end
    draft ||= current_business.ventas.new(status: "draft")
    requested_visibility = normalize_draft_visibility(payload[:draft_visibility], default: draft_visibility(draft))

    service_item_rows = []

    begin
      Venta.transaction do
        if draft.persisted?
          restore_stock_for_sale!(draft)
          draft.venta_items.destroy_all
          draft.venta_payments.destroy_all
        end

        draft.assign_attributes(
          status: "draft",
          vat_mode: vat_mode,
          vat_rate: vat_rate,
          tasa_dolar: tasa_dolar,
          base_currency: base_currency,
        )

        if payload[:cliente_id].present?
          cliente = current_business.clientes.find_by(id: payload[:cliente_id])
          draft.cliente = cliente
        else
          draft.cliente = nil
        end

        items.each do |item|
          item_type = item[:item_type].to_s
          if item_type == "service" || item[:service_id].present?
            service = current_business
              .services
              .includes(:system_service,
                        service_expense_structures: %i[service_product_expenses
                                                       service_nested_expenses])
              .find_by(id: item[:service_id])
            next unless service

            quantity = parse_decimal(item[:quantity], default: 0)
            next unless quantity.positive?

            unit_price_usd = if service.to_agree?
                parse_decimal(item[:unit_price_usd], default: 0)
              else
                service_unit_price_usd(service, tasa_dolar)
              end

            if unit_price_usd.nil? || unit_price_usd.to_d <= 0
              message = service.to_agree? ? "Debes indicar el precio acordado del servicio." : "No se pudo calcular el precio del servicio."
              raise ActiveRecord::RecordInvalid.new(draft), message
            end

            draft.venta_items.build(
              product_name: service.description.to_s,
              variation_name: service.system_service&.name.presence || "Servicio",
              quantity: quantity,
              unit_price_usd: unit_price_usd,
            )

            service_item_rows << {
              service: service,
              quantity: quantity,
              payload: item.to_h,
            }

            next
          end

          product = current_business.productos.includes(:product_variations).find_by(id: item[:product_id])
          next unless product

          quantity = parse_decimal(item[:quantity], default: 0)
          next unless quantity.positive?

          variation = (product.product_variations.find_by(id: item[:variation_id]) if item[:variation_id].present?)
          variation ||= product.product_variations.order(:id).first
          next unless variation

          unit_price = product.precio_venta_usd.to_d
          unit_price /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive?

          draft.venta_items.build(
            producto: product,
            product_variation: variation,
            quantity: quantity,
            unit_price_usd: unit_price,
          )
        end

        if draft.venta_items.empty?
          raise ActiveRecord::RecordInvalid.new(draft), "No hay items validos para guardar el borrador."
        end

        draft.save!

        reserve_product_stock_for_sale!(draft)
        reserved_service_products = reserve_service_product_expenses_for_items!(service_item_rows, venta: draft)

        notes_payload = parse_notes_payload(draft.notes)
        notes_payload["draft_state"] = {
          "vat_mode" => draft.vat_mode,
          "vat_rate" => draft.vat_rate.to_d.to_f,
          "tasa_dolar" => draft.tasa_dolar.to_d.to_f,
          "base_currency" => draft.base_currency,
          "cliente_id" => draft.cliente_id,
          "items" => items.map { |entry| normalize_item_payload(entry) },
        }
        notes_payload["draft_visibility"] = requested_visibility
        notes_payload["reserved_product_items"] = reserved_product_items_payload_for_sale(draft)
        notes_payload["reserved_service_products"] = reserved_service_products
        draft.update!(notes: serialize_notes_payload(notes_payload))
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message.presence || "No se pudo guardar el borrador." },
                    status: :unprocessable_entity
    end

    render json: {
      draft: draft_summary_payload(draft).merge(
        state: draft_state_payload(draft),
        client: draft_client_payload(draft),
      ),
      drafts: drafts_payload,
      products: products_payload_for_business,
    }
  end

  def normalize_item_payload(entry)
    raw_hash = if entry.respond_to?(:to_unsafe_h)
        entry.to_unsafe_h
      elsif entry.respond_to?(:to_h)
        entry.to_h
      else
        {}
      end

    raw_hash.deep_stringify_keys
  end

  def products_payload_for_business
    productos = current_business
      .productos
      .includes(:product_variations, :stock_lot_variations, :stock_lots)
      .order(:descripcion)

    build_products_payload(productos)
  end

  def build_products_payload(productos)
    productos.map do |producto|
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
          available: available.to_f,
        }
      end

      {
        id: producto.id,
        name: producto.descripcion.to_s,
        price_usd: producto.precio_venta_usd.to_f,
        available_total: total_units.to_f,
        variations: variations_payload,
      }
    end
  end

  def drafts_payload
    current_business
      .ventas
      .where(status: "draft")
      .includes(:cliente, :venta_items)
      .order(updated_at: :desc)
      .limit(120)
      .first(40)
      .map { |draft| draft_summary_payload(draft) }
  end

  def draft_summary_payload(venta)
    {
      id: venta.id,
      client_name: venta.cliente_display_name,
      items_count: venta.venta_items.size,
      base_currency: venta.base_currency,
      total_usd: venta.total_usd.to_d.to_f,
      total_bs: venta.total_bs.to_d.to_f,
      updated_at: venta.updated_at&.iso8601,
      visibility: draft_visibility(venta),
    }
  end

  def draft_client_payload(venta)
    cliente = venta.cliente
    return nil unless cliente

    document = [cliente.document_type.to_s.strip, cliente.document_number.to_s.strip].reject(&:blank?).join("-")

    {
      id: cliente.id,
      name: cliente.name.to_s,
      document: document,
    }
  end

  def draft_state_payload(venta)
    notes_payload = parse_notes_payload(venta.notes)
    state = notes_payload["draft_state"]
    return state if state.is_a?(Hash)

    {
      "vat_mode" => venta.vat_mode,
      "vat_rate" => venta.vat_rate.to_d.to_f,
      "tasa_dolar" => venta.tasa_dolar.to_d.to_f,
      "base_currency" => venta.base_currency,
      "cliente_id" => venta.cliente_id,
      "items" => venta.venta_items.map do |item|
        if item.producto_id.present?
          {
            "item_type" => "product",
            "product_id" => item.producto_id,
            "variation_id" => item.product_variation_id,
            "quantity" => item.quantity.to_d.to_f,
            "unit_price_usd" => item.unit_price_usd.to_d.to_f,
          }
        else
          {
            "item_type" => "service",
            "service_id" => nil,
            "quantity" => item.quantity.to_d.to_f,
            "unit_price_usd" => item.unit_price_usd.to_d.to_f,
          }
        end
      end,
    }
  end

  def parse_notes_payload(raw_notes)
    return {} if raw_notes.blank?

    parsed = JSON.parse(raw_notes)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def serialize_notes_payload(payload)
    return nil unless payload.is_a?(Hash)

    compacted = payload.compact
    compacted.empty? ? nil : compacted.to_json
  end

  def reserve_product_stock_for_sale!(venta)
    grouped_items = venta.venta_items
                         .select { |item| item.producto_id.present? && item.product_variation_id.present? }
                         .group_by { |item| [item.producto_id, item.product_variation_id] }

    grouped_items.each do |(producto_id, variation_id), grouped_rows|
      quantity_units = grouped_rows.sum { |row| row.quantity.to_d }
      next unless quantity_units.positive?

      producto = current_business.productos.find_by(id: producto_id)
      next unless producto

      producto.consume_variation_stock!(variation_id: variation_id, quantity_units: quantity_units)
    end
  end

  def reserve_service_product_expenses_for_items!(service_item_rows, venta:)
    grouped = Hash.new(0.to_d)

    service_item_rows.each do |entry|
      service = entry[:service]
      quantity_multiplier = entry[:quantity].to_d
      next unless service && quantity_multiplier.positive?
      next unless service.auto_cost_stock_discount?

      consumable_decisions = normalize_service_product_decisions(entry[:payload])

      collect_service_product_consumptions!(
        service: service,
        multiplier: quantity_multiplier,
        grouped: grouped,
        visited_service_ids: [],
        consumable_decisions: consumable_decisions,
      )
    end

    reservations = []
    grouped.each do |(producto_id, variation_id), quantity_units|
      next unless quantity_units.positive?

      producto = current_business.productos.find_by(id: producto_id)
      next unless producto

      producto.consume_variation_stock!(variation_id: variation_id, quantity_units: quantity_units)
      reservations << {
        "product_id" => producto_id,
        "variation_id" => variation_id,
        "quantity" => quantity_units.to_d.to_f,
      }
    end

    reservations
  rescue ActiveRecord::RecordInvalid => e
    raise ActiveRecord::RecordInvalid.new(venta), e.message
  end

  def collect_service_product_consumptions!(service:, multiplier:, grouped:, visited_service_ids:,
                                            consumable_decisions: {})
    return unless service
    return unless multiplier.to_d.positive?
    return if service.business_id.present? && service.business_id != current_business.id

    service_id = service.id
    return if service_id.present? && visited_service_ids.include?(service_id)

    next_visited = visited_service_ids.dup
    next_visited << service_id if service_id.present?

    service.service_expense_structures.where(active_for_sales: true).includes(
      {
        service_product_expenses: [:product_variation, { producto: :product_variations }],
      },
      { service_nested_expenses: :nested_service }
    ).each do |structure|
      structure.service_product_expenses.each do |expense|
        decision = consumable_decisions[expense.id.to_s] || {}
        delivered = if decision.key?("delivered")
            ActiveModel::Type::Boolean.new.cast(decision["delivered"])
          else
            true
          end
        next unless delivered

        producto = expense.producto
        next unless producto
        next if producto.business_id != current_business.id

        variation_override_id = decision["product_variation_id"]
        variation = producto.product_variations.find_by(id: variation_override_id) if variation_override_id.present?
        variation ||= expense.product_variation
        variation = nil if variation.present? && variation.producto_id != producto.id
        variation ||= producto.product_variations.to_a.min_by(&:id)
        variation_id = variation&.id
        next if variation_id.blank?

        required_units = expense.quantity.to_d * multiplier.to_d
        next unless required_units.positive?

        grouped[[producto.id, variation_id]] += required_units
      end

      structure.service_nested_expenses.each do |nested|
        nested_service = nested.nested_service
        next unless nested_service
        next if nested_service.business_id.present? && nested_service.business_id != current_business.id

        nested_multiplier = multiplier.to_d * nested.quantity.to_d
        next unless nested_multiplier.positive?

        collect_service_product_consumptions!(
          service: nested_service,
          multiplier: nested_multiplier,
          grouped: grouped,
          visited_service_ids: next_visited,
          consumable_decisions: {},
        )
      end
    end
  end

  def restore_reserved_service_stock_from_notes!(venta)
    notes_payload = parse_notes_payload(venta.notes)
    rows = Array(notes_payload["reserved_service_products"])
    rows.each do |row|
      producto_id = row["product_id"] || row[:product_id]
      variation_id = row["variation_id"] || row[:variation_id]
      quantity_units = parse_decimal(row["quantity"] || row[:quantity], default: 0)
      next if producto_id.blank? || variation_id.blank? || !quantity_units.positive?

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
      )
    end
  end

  def venta_params
    params.require(:venta).permit(
      :draft_id,
      :draft_visibility,
      :vat_mode,
      :vat_rate,
      :tasa_dolar,
      :base_currency,
      :cliente_id,
      items: [
        :item_type,
        :product_id,
        :service_id,
        :variation_id,
        :quantity,
        :unit_price_usd,
        :unit_price_base_amount,
        :unit_price_base_currency,
        :agreed_price_display,
        :agreed_reference_name,
        :agreed_reference_amount,
        :agreed_reference_symbol,
        :price_signature,
        { nested_agreements: %i[nested_expense_id amount_reference currency_reference] },
        { consumable_decisions: %i[service_product_expense_id delivered product_variation_id] },
      ],
      payments: %i[method amount account_id currency reference payment_date],
      change: %i[method amount account_id currency reference],
      credit_sale: %i[enabled due_on],
      service_cost_payments: %i[
        service_id
        pay_now
        account_id
        amount
        currency
        payment_method
        reference
        payment_date
      ],
    )
  end

  def draft_visibility(venta)
    return "visible" unless venta

    notes_payload = parse_notes_payload(venta.notes)
    normalize_draft_visibility(notes_payload["draft_visibility"], default: "visible")
  end

  def normalize_draft_visibility(value, default: "visible")
    normalized = value.to_s.strip.downcase
    return normalized if %w[visible hidden].include?(normalized)

    fallback = default.to_s.strip.downcase
    return fallback if %w[visible hidden].include?(fallback)

    "visible"
  end

  def reserved_product_items_payload_for_sale(venta)
    venta
      .venta_items
      .select { |item| item.producto_id.present? && item.product_variation_id.present? }
      .group_by { |item| [item.producto_id, item.product_variation_id] }
      .map do |(producto_id, variation_id), grouped_items|
      {
        "product_id" => producto_id,
        "variation_id" => variation_id,
        "quantity" => grouped_items.sum { |row| row.quantity.to_d }.to_d.to_f,
      }
    end
      .select { |row| row["quantity"].to_d.positive? }
  end

  def service_cost_settlements_payload_for_notes(settlements)
    Array(settlements).map do |row|
      service = row[:service]

      {
        "service_id" => service&.id,
        "service_name" => service&.description.to_s,
        "quantity" => row[:quantity].to_d.to_f,
        "unit_cost_usd" => row[:unit_cost_usd].to_d.to_f,
        "total_cost_usd" => row[:total_cost_usd].to_d.to_f,
        "paid_cost_usd" => row[:paid_cost_usd].to_d.to_f,
        "pending_cost_usd" => row[:pending_cost_usd].to_d.to_f,
        "detail_lines" => normalize_service_cost_lines_payload(row[:detail_lines]),
      }
    end
  end

  def build_service_cost_obligations(service_item_rows:, tasa_dolar:)
    grouped_rows = Hash.new do |hash, key|
      hash[key] = {
        service: nil,
        quantity: 0.to_d,
        nested_overrides: {},
        consumable_decisions: {},
      }
    end

    service_item_rows.each do |entry|
      service = entry[:service]
      quantity = entry[:quantity].to_d
      next unless service
      next unless service.id.present?
      next unless quantity.positive?
      next unless service.auto_cost_stock_discount?

      grouped_rows[service.id][:service] = service
      grouped_rows[service.id][:quantity] += quantity

      normalize_nested_cost_overrides(entry[:payload]).each do |expense_id, override_row|
        grouped_rows[service.id][:nested_overrides][expense_id.to_s] = override_row
      end

      normalize_service_product_decisions(entry[:payload]).each do |expense_id, decision_row|
        grouped_rows[service.id][:consumable_decisions][expense_id.to_s] = decision_row
      end
    end

    unidad_vi = parse_decimal(@unidad_VI, default: TasaCambio.latest_value("Unidad VI"))
    obligations = []

    grouped_rows.each_value do |row|
      service = row[:service]
      quantity = row[:quantity].to_d
      next unless service
      next unless quantity.positive?

      unit_cost_usd = service.total_expense_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi, active_only: true).to_d.round(2)
      next unless unit_cost_usd.positive?

      total_cost_usd = (unit_cost_usd * quantity).round(2)
      next unless total_cost_usd.positive?

      detail_lines = build_service_cost_detail_lines(
        service: service,
        multiplier: quantity,
        tasa_dolar: tasa_dolar,
        unidad_vi: unidad_vi,
        nested_overrides: row[:nested_overrides],
        consumable_decisions: row[:consumable_decisions],
      )

      if detail_lines.empty?
        detail_lines << {
          "line_id" => "service-#{service.id}-generic",
          "service_id" => service.id,
          "service_name" => service.description.to_s,
          "structure_id" => nil,
          "structure_description" => "Estructura general",
          "classification" => "general",
          "classification_label" => "Costo general",
          "source_type" => nil,
          "source_id" => nil,
          "source_name" => service.description.to_s,
          "quantity" => quantity.to_d.to_f,
          "amount_usd" => total_cost_usd.to_d.to_f,
          "paid_usd" => 0.0,
          "pending_usd" => total_cost_usd.to_d.to_f,
          "status" => "pending",
          "source_updatable" => false,
          "source_currency_reference" => nil,
        }
      else
        lines_total_usd = detail_lines.sum { |line| line["amount_usd"].to_d }.round(2)
        difference = (total_cost_usd - lines_total_usd).round(2)

        if difference.abs > 0.01.to_d
          last_line = detail_lines.last
          adjusted_amount = (last_line["amount_usd"].to_d + difference).round(2)

          if adjusted_amount.positive?
            last_line["amount_usd"] = adjusted_amount.to_f
            last_line["pending_usd"] = adjusted_amount.to_f
          else
            detail_lines << {
              "line_id" => "service-#{service.id}-adjustment",
              "service_id" => service.id,
              "service_name" => service.description.to_s,
              "structure_id" => nil,
              "structure_description" => "Ajuste de redondeo",
              "classification" => "adjustment",
              "classification_label" => "Ajuste",
              "source_type" => nil,
              "source_id" => nil,
              "source_name" => "Ajuste de redondeo",
              "quantity" => 1.0,
              "amount_usd" => difference.to_d.abs.to_f,
              "paid_usd" => 0.0,
              "pending_usd" => difference.to_d.abs.to_f,
              "status" => "pending",
              "source_updatable" => false,
              "source_currency_reference" => nil,
            }
          end
        end
      end

      obligations << {
        service: service,
        service_id: service.id,
        quantity: quantity,
        unit_cost_usd: unit_cost_usd,
        total_cost_usd: total_cost_usd,
        detail_lines: detail_lines,
      }
    end

    [obligations, nil]
  end

  def build_service_cost_detail_lines(service:, multiplier:, tasa_dolar:, unidad_vi:, nested_overrides: {},
                                      consumable_decisions: {})
    return [] unless service

    line_sequence = 0
    lines = []

    service.service_expense_structures.where(active_for_sales: true).includes(
      { service_manager_expenses: :manager },
      :service_variable_expenses,
      { service_nested_expenses: :nested_service },
      { service_product_expenses: %i[producto product_variation] }
    ).each do |structure|
      structure_label = structure.description.to_s.strip.presence || "Estructura ##{structure.id}"

      structure.service_manager_expenses.each do |expense|
        amount_usd = (expense.current_amount_usd(tasa_dolar: tasa_dolar).to_d * multiplier.to_d).round(2)
        next unless amount_usd.positive?
        reference_unit_amount = expense.amount_reference.to_d.round(2)
        reference_total_amount = (reference_unit_amount * multiplier.to_d).round(2)

        line_sequence += 1
        lines << {
          "line_id" => "service-#{service.id}-line-#{line_sequence}",
          "service_id" => service.id,
          "service_name" => service.description.to_s,
          "structure_id" => structure.id,
          "structure_description" => structure_label,
          "classification" => "manager_expense",
          "classification_label" => "Gestor",
          "source_type" => "ServiceManagerExpense",
          "source_id" => expense.id,
          "source_name" => expense.manager&.name.to_s.strip.presence || "Gestor",
          "quantity" => multiplier.to_d.to_f,
          "amount_usd" => amount_usd.to_d.to_f,
          "paid_usd" => 0.0,
          "pending_usd" => amount_usd.to_d.to_f,
          "status" => "pending",
          "source_updatable" => true,
          "source_currency_reference" => expense.currency_reference.to_s,
          "source_amount_reference_unit" => reference_unit_amount.to_f,
          "source_amount_reference_total" => reference_total_amount.to_f,
        }
      end

      structure.service_variable_expenses.each do |expense|
        amount_usd = (expense.current_amount_usd(tasa_dolar: tasa_dolar).to_d * multiplier.to_d).round(2)
        next unless amount_usd.positive?
        reference_unit_amount = expense.amount_reference.to_d.round(2)
        reference_total_amount = (reference_unit_amount * multiplier.to_d).round(2)

        line_sequence += 1
        lines << {
          "line_id" => "service-#{service.id}-line-#{line_sequence}",
          "service_id" => service.id,
          "service_name" => service.description.to_s,
          "structure_id" => structure.id,
          "structure_description" => structure_label,
          "classification" => "variable_expense",
          "classification_label" => "Gasto variable",
          "source_type" => "ServiceVariableExpense",
          "source_id" => expense.id,
          "source_name" => expense.description.to_s.strip.presence || "Gasto variable",
          "quantity" => multiplier.to_d.to_f,
          "amount_usd" => amount_usd.to_d.to_f,
          "paid_usd" => 0.0,
          "pending_usd" => amount_usd.to_d.to_f,
          "status" => "pending",
          "source_updatable" => true,
          "source_currency_reference" => expense.currency_reference.to_s,
          "source_amount_reference_unit" => reference_unit_amount.to_f,
          "source_amount_reference_total" => reference_total_amount.to_f,
        }
      end

      structure.service_nested_expenses.each do |expense|
        override = nested_overrides[expense.id.to_s] || {}
        selected_reference = override["currency_reference"].to_s.strip.presence || expense.currency_reference.to_s
        selected_reference_amount = parse_decimal(
          override["amount_reference"],
          default: expense.amount_reference,
        ).round(2)

        amount_usd = if expense.nested_service&.to_agree? && override.present?
            selected_unit_usd = reference_amount_to_usd(
              amount_reference: selected_reference_amount,
              reference: selected_reference,
              tasa_dolar: tasa_dolar,
            )
            (selected_unit_usd.to_d * multiplier.to_d).round(2)
          else
            (expense.total_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d * multiplier.to_d).round(2)
          end
        next unless amount_usd.positive?

        line_sequence += 1
        nested_name = expense.nested_service&.description.to_s.strip.presence || "Servicio anidado"
        lines << {
          "line_id" => "service-#{service.id}-line-#{line_sequence}",
          "service_id" => service.id,
          "service_name" => service.description.to_s,
          "structure_id" => structure.id,
          "structure_description" => structure_label,
          "classification" => "nested_expense",
          "classification_label" => "Servicio anidado",
          "source_type" => "ServiceNestedExpense",
          "source_id" => expense.id,
          "source_name" => nested_name,
          "quantity" => (expense.quantity.to_d * multiplier.to_d).to_f,
          "amount_usd" => amount_usd.to_d.to_f,
          "paid_usd" => 0.0,
          "pending_usd" => amount_usd.to_d.to_f,
          "status" => "pending",
          "source_updatable" => false,
          "source_currency_reference" => selected_reference,
          "source_amount_reference_unit" => selected_reference_amount.to_f,
          "source_amount_reference_total" => (selected_reference_amount.to_d * multiplier.to_d).round(2).to_f,
        }
      end

      structure.service_product_expenses.each do |expense|
        decision = consumable_decisions[expense.id.to_s] || {}
        delivered = if decision.key?("delivered")
            ActiveModel::Type::Boolean.new.cast(decision["delivered"])
          else
            true
          end
        next unless delivered

        amount_usd = (expense.total_usd.to_d * multiplier.to_d).round(2)
        next unless amount_usd.positive?

        line_sequence += 1
        product_name = expense.producto&.descripcion.to_s.strip.presence || "Producto"
        variation_name = expense.product_variation&.description.to_s.strip.presence

        lines << {
          "line_id" => "service-#{service.id}-line-#{line_sequence}",
          "service_id" => service.id,
          "service_name" => service.description.to_s,
          "structure_id" => structure.id,
          "structure_description" => structure_label,
          "classification" => "product_expense",
          "classification_label" => "Consumible",
          "source_type" => "ServiceProductExpense",
          "source_id" => expense.id,
          "source_name" => variation_name.present? ? "#{product_name} (#{variation_name})" : product_name,
          "quantity" => (expense.quantity.to_d * multiplier.to_d).to_f,
          "amount_usd" => amount_usd.to_d.to_f,
          "paid_usd" => 0.0,
          "pending_usd" => amount_usd.to_d.to_f,
          "status" => "pending",
          "source_updatable" => false,
          "source_currency_reference" => nil,
        }
      end
    end

    lines
  end

  def normalize_service_product_decisions(payload)
    source = payload.respond_to?(:to_h) ? payload.to_h : {}
    rows = source["consumable_decisions"] || source[:consumable_decisions]

    Array(rows).each_with_object({}) do |raw_row, hash|
      row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
      expense_id = (row["service_product_expense_id"] || row[:service_product_expense_id]).to_s.strip
      next if expense_id.blank?

      delivered = ActiveModel::Type::Boolean.new.cast(row["delivered"] || row[:delivered])
      variation_id = row["product_variation_id"] || row[:product_variation_id]

      hash[expense_id] = {
        "service_product_expense_id" => expense_id,
        "delivered" => delivered,
        "product_variation_id" => variation_id,
      }
    end
  end

  def normalize_nested_cost_overrides(payload)
    source = payload.respond_to?(:to_h) ? payload.to_h : {}
    rows = source["nested_agreements"] || source[:nested_agreements]

    Array(rows).each_with_object({}) do |raw_row, hash|
      row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
      nested_expense_id = (row["nested_expense_id"] || row[:nested_expense_id]).to_s.strip
      next if nested_expense_id.blank?

      amount_reference = parse_decimal(row["amount_reference"] || row[:amount_reference], default: 0)
      next unless amount_reference.positive?

      currency_reference = (row["currency_reference"] || row[:currency_reference]).to_s.strip
      currency_reference = "Bs" if currency_reference.blank?

      hash[nested_expense_id] = {
        "nested_expense_id" => nested_expense_id,
        "amount_reference" => amount_reference.to_d.to_f,
        "currency_reference" => currency_reference,
      }
    end
  end

  def reference_amount_to_usd(amount_reference:, reference:, tasa_dolar:)
    reference_amount_decimal = amount_reference.to_d
    return 0.to_d unless reference_amount_decimal.positive?

    reference_name = reference.to_s.strip.presence || "Bs"
    reference_rate_bs = if reference_name == "Bs"
        1.to_d
      else
        TasaCambio.latest_value(reference_name).to_d
      end
    return 0.to_d unless reference_rate_bs.positive?

    bcv_rate = tasa_dolar.to_d
    bcv_rate = TasaCambio.latest_value("Dolar BCV").to_d unless bcv_rate.positive?
    return 0.to_d unless bcv_rate.positive?

    ((reference_amount_decimal * reference_rate_bs) / bcv_rate).round(2)
  end

  def normalize_service_cost_lines_payload(lines)
    Array(lines).map do |raw_line|
      line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}
      amount_usd = parse_decimal(line["amount_usd"], default: 0).round(2)
      paid_usd = parse_decimal(line["paid_usd"], default: 0).round(2)
      paid_usd = amount_usd if paid_usd > amount_usd

      pending_usd = (amount_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      status = if pending_usd <= 0
          "paid"
        elsif paid_usd.positive?
          "partial"
        else
          "pending"
        end

      line.merge(
        "line_id" => line["line_id"].to_s.presence || "line-#{SecureRandom.hex(4)}",
        "amount_usd" => amount_usd.to_f,
        "paid_usd" => paid_usd.to_f,
        "pending_usd" => pending_usd.to_f,
        "status" => status,
      )
    end
  end

  def build_service_cost_settlements(obligations:, raw_rows:, tasa_dolar:)
    return [[], nil] if obligations.blank?

    rows_by_service_id = Array(raw_rows).each_with_object({}) do |raw_row, hash|
      source = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
      service_id = source["service_id"] || source[:service_id]
      next if service_id.blank?

      hash[service_id.to_s] = source
    end

    settlements = []
    today = Time.use_zone("America/Caracas") { Time.zone.today }

    obligations.each do |obligation|
      service = obligation[:service]
      service_label = service&.description.to_s.presence || "##{obligation[:service_id]}"
      raw_row = rows_by_service_id[obligation[:service_id].to_s] || {}

      pay_now = ActiveModel::Type::Boolean.new.cast(raw_row["pay_now"] || raw_row[:pay_now])
      paid_cost_usd = 0.to_d
      payment_row = nil

      if pay_now
        account_id = raw_row["account_id"] || raw_row[:account_id]
        account = current_business.accounts.find_by(id: account_id)
        if account.blank?
          return [nil,
                  "Selecciona una cuenta para registrar el pago inmediato del costo de #{service_label}."]
        end

        amount_original = parse_decimal(raw_row["amount"] || raw_row[:amount], default: 0).round(2)
        unless amount_original.positive?
          return [nil, "Indica un monto valido para el pago inmediato del costo de #{service_label}."]
        end

        currency = normalize_currency(raw_row["currency"] || raw_row[:currency], default: account.currency || "USD")
        amount_usd = convert_payment_to_usd(amount_original, currency, tasa_dolar)
        return [nil, "No se pudo convertir el pago inmediato del costo de #{service_label} a USD."] if amount_usd.nil?

        total_cost_usd = obligation[:total_cost_usd].to_d
        if amount_usd.to_d > total_cost_usd + 0.01.to_d
          return [nil, "El pago inmediato del costo de #{service_label} excede el costo estimado."]
        end

        payment_method = (raw_row["payment_method"] || raw_row[:payment_method]).to_s.strip
        payment_method = default_method_for_account(account) if payment_method.blank?

        reference = (raw_row["reference"] || raw_row[:reference]).to_s.strip
        payment_date_raw = raw_row["payment_date"] || raw_row[:payment_date]
        payment_date = parse_payment_date(payment_date_raw)

        if account.account_type == "bank_account"
          unless %w[transfer mobile].include?(payment_method)
            return [nil, "Selecciona transferencia o pago movil para el costo de #{service_label}."]
          end

          unless valid_reference?(reference)
            return [nil, "La referencia del pago de costo para #{service_label} debe tener 6 digitos."]
          end

          return [nil, "Debes indicar la fecha del pago de costo para #{service_label}."] if payment_date.blank?
        end

        payment_date ||= today

        paid_cost_usd = amount_usd.to_d.round(2)
        payment_row = {
          account: account,
          amount_original: amount_original,
          amount_usd: paid_cost_usd,
          currency: currency,
          payment_method: payment_method,
          debt_payment_method: (account.account_type == "bank_account" ? payment_method : nil),
          reference: reference.presence,
          payment_date: payment_date,
        }
      end

      pending_cost_usd = (obligation[:total_cost_usd].to_d - paid_cost_usd).round(2)
      pending_cost_usd = 0.to_d if pending_cost_usd.abs <= 0.01.to_d

      settlements << obligation.merge(
        pay_now: pay_now,
        paid_cost_usd: paid_cost_usd,
        pending_cost_usd: pending_cost_usd,
        payment_row: payment_row,
      )
    end

    [settlements, nil]
  end

  def register_service_cost_settlements_for_sale!(venta:, settlements:)
    return if settlements.blank?

    issued_on = Time.use_zone("America/Caracas") { Time.zone.today }

    settlements.each do |settlement|
      service = settlement[:service]
      next unless service

      total_cost_usd = settlement[:total_cost_usd].to_d.round(2)
      paid_cost_usd = settlement[:paid_cost_usd].to_d.round(2)
      payment_row = settlement[:payment_row]
      detail_lines = normalize_service_cost_lines_payload(settlement[:detail_lines])
      detail_lines = apply_paid_amount_to_service_cost_lines(
        lines: detail_lines,
        paid_amount_usd: paid_cost_usd,
      )

      details_payload = build_service_cost_details_payload_for_debt(
        settlement: settlement,
        lines: detail_lines,
      )
      pending_cost_usd = details_payload["pending_usd"].to_d.round(2)

      next unless total_cost_usd.positive?

      if pending_cost_usd.positive?
        debt = current_business.debts.create!(
          name: "Costo servicio ##{service.id} - Venta ##{venta.id}",
          description: "Costo pendiente servicio #{service.description} [SERVICE:#{service.id}] [VENTA:#{venta.id}] [SERVICE_COST]",
          debt_kind: "payable",
          amount: total_cost_usd,
          currency: "USD",
          issued_on: issued_on,
          venta: venta,
          service: service,
          service_cost_pending: true,
          service_cost_details: details_payload,
        )

        if paid_cost_usd.positive? && payment_row.present?
          debt.debt_payments.create!(
            account: payment_row[:account],
            amount: payment_row[:amount_original],
            currency: payment_row[:currency],
            payment_method: payment_row[:debt_payment_method],
            reference: payment_row[:reference],
            occurred_at: payment_row[:payment_date],
            notes: "Pago inicial costo servicio venta ##{venta.id} [VENTA:#{venta.id}] [SERVICE:#{service.id}] [SERVICE_COST]",
          )
        end

        next
      end

      next unless paid_cost_usd.positive? && payment_row.present?

      movement_attrs = {
        movement_kind: "expense",
        amount: payment_row[:amount_original].to_d,
        description: build_service_cost_movement_description(venta: venta, service: service,
                                                             reference: payment_row[:reference]),
        occurred_at: payment_row[:payment_date].in_time_zone("America/Caracas").end_of_day,
      }

      if payment_row[:account].account_type == "bank_account" && %w[transfer
                                                                    mobile].include?(payment_row[:payment_method])
        movement_attrs[:payment_method] = normalize_account_movement_method(payment_row[:payment_method])
      end

      payment_row[:account].account_movements.create!(movement_attrs)
    end
  end

  def apply_paid_amount_to_service_cost_lines(lines:, paid_amount_usd:)
    normalized_lines = normalize_service_cost_lines_payload(lines)
    remaining_paid = paid_amount_usd.to_d.round(2)

    normalized_lines.each do |line|
      break if remaining_paid <= 0

      pending_usd = line["pending_usd"].to_d
      next unless pending_usd.positive?

      allocation = [remaining_paid, pending_usd].min.round(2)
      next unless allocation.positive?

      paid_usd = (line["paid_usd"].to_d + allocation).round(2)
      pending_usd = (line["amount_usd"].to_d - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      line["paid_usd"] = paid_usd.to_f
      line["pending_usd"] = pending_usd.to_f
      line["status"] = pending_usd <= 0 ? "paid" : "partial"

      remaining_paid = (remaining_paid - allocation).round(2)
    end

    normalized_lines
  end

  def build_service_cost_details_payload_for_debt(settlement:, lines:)
    normalized_lines = normalize_service_cost_lines_payload(lines)
    total_usd = settlement[:total_cost_usd].to_d.round(2)
    paid_usd = normalized_lines.sum { |line| line["paid_usd"].to_d }.round(2)
    pending_usd = normalized_lines.sum { |line| line["pending_usd"].to_d }.round(2)

    status = if pending_usd <= 0.01.to_d
        "paid"
      elsif paid_usd.positive?
        "partial"
      else
        "pending"
      end

    {
      "version" => 1,
      "service_id" => settlement[:service_id],
      "service_name" => settlement[:service]&.description.to_s,
      "total_usd" => total_usd.to_f,
      "paid_usd" => paid_usd.to_f,
      "pending_usd" => pending_usd.to_f,
      "status" => status,
      "lines" => normalized_lines,
    }
  end

  def build_service_cost_movement_description(venta:, service:, reference: nil)
    base = "Costo servicio #{service.description} venta ##{venta.id} [VENTA:#{venta.id}] [SERVICE:#{service.id}] [SERVICE_COST]"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
  end

  def service_unit_price_usd(service, tasa_dolar)
    return nil unless service

    service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: parse_decimal(@unidad_VI, default: 0))
  end

  def parse_decimal(value, default: 0)
    return default.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.tr(",", ".")
    BigDecimal(cleaned)
  rescue ArgumentError
    default.to_d
  end

  def normalize_currency(value, default: "USD")
    normalized = value.to_s.strip.upcase
    return default if normalized.blank?

    normalized
  end

  def convert_payment_to_usd(amount, currency, tasa_dolar)
    return amount.to_d.round(2) if %w[USD USDT].include?(currency)

    if currency == "VES"
      rate = tasa_dolar.to_d
      return nil unless rate.positive?

      return (amount.to_d / rate).round(2)
    end

    amount.to_d.round(2)
  end

  def convert_payment_to_currency(amount, currency, target_currency, tasa_dolar)
    from_currency = normalize_currency(currency, default: target_currency)
    to_currency = normalize_currency(target_currency, default: "USD")
    return amount.to_d.round(2) if from_currency == to_currency

    rate = tasa_dolar.to_d
    if from_currency == "VES" && %w[USD USDT].include?(to_currency)
      return nil unless rate.positive?

      return (amount.to_d / rate).round(2)
    end

    if %w[USD USDT].include?(from_currency) && to_currency == "VES"
      return nil unless rate.positive?

      return (amount.to_d * rate).round(2)
    end

    amount.to_d.round(2)
  end

  def total_due_in_currency(venta, currency, tasa_dolar)
    return venta.total_usd.to_d.round(2) unless currency == "VES"

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
      "#{label} venta ##{venta.id} [VENTA:#{venta.id}] - Ref #{reference}"
    else
      "#{label} venta ##{venta.id} [VENTA:#{venta.id}]"
    end
  end

  def normalize_account_movement_method(method)
    return "mobile_payment" if method.to_s == "mobile"

    method.to_s
  end

  def normalize_credit_sale_payload(raw_payload)
    source = raw_payload.respond_to?(:to_h) ? raw_payload.to_h : {}
    enabled_value = source["enabled"] || source[:enabled]
    due_on_value = source["due_on"] || source[:due_on]

    {
      enabled: ActiveModel::Type::Boolean.new.cast(enabled_value),
      due_on: due_on_value.to_s.strip.presence,
    }
  end

  def load_sale_credit_context!
    sale_tag = "[VENTA:#{@venta.id}]"
    linked_debts = current_business
      .debts
      .includes(:debt_payments)
      .where(debt_kind: "receivable")
      .where("description LIKE ?", "%#{sale_tag}%")
      .order(created_at: :desc)
      .to_a

    @sale_linked_debts = linked_debts
    @sale_linked_debt = linked_debts.first

    debt_currency = @sale_linked_debt&.currency.to_s.upcase.presence || @venta.base_currency.to_s.upcase
    same_currency_debts = linked_debts.select { |debt| debt.currency.to_s.upcase == debt_currency }

    debt_total = same_currency_debts.sum { |debt| debt.amount.to_d }.round(2)
    debt_paid = same_currency_debts.sum { |debt| debt.paid_amount.to_d }.round(2)
    debt_balance = [debt_total - debt_paid, 0.to_d].max.round(2)

    @sale_credit_totals = {
      currency: debt_currency,
      total: debt_total,
      paid: debt_paid,
      balance: debt_balance,
    }

    has_sale_payments = @venta.venta_payments.any? { |payment| payment.payment_kind == "in" }
    @sale_credit_status = sale_credit_status_for(
      total: debt_total,
      paid: debt_paid,
      balance: debt_balance,
      has_payments: has_sale_payments,
    )

    @invoice_status = if @sale_linked_debt.present?
        @sale_credit_status
      else
        sale_credit_status_for(total: 0, paid: 0, balance: 0)
      end

    @sale_credit_display = build_sale_credit_display(
      totals: @sale_credit_totals,
      base_currency: @venta.base_currency,
      rate: @sale_reference[:effective_usd_rate].to_d,
    )
  end

  def sale_credit_status_for(total:, paid:, balance:, has_payments: false)
    total_value = total.to_d
    paid_value = paid.to_d
    balance_value = balance.to_d

    if total_value <= 0 || balance_value <= 0
      {
        key: "paid",
        label: "Pagada",
        badge_class: "bg-emerald-100 text-emerald-700 ring-1 ring-emerald-200",
      }
    elsif paid_value.positive? || has_payments
      {
        key: "partial",
        label: "Parcial",
        badge_class: "bg-amber-100 text-amber-700 ring-1 ring-amber-200",
      }
    else
      {
        key: "pending",
        label: "Pendiente",
        badge_class: "bg-rose-100 text-rose-700 ring-1 ring-rose-200",
      }
    end
  end

  def build_sale_credit_display(totals:, base_currency:, rate:)
    debt_currency = totals[:currency].to_s.upcase
    base_currency_code = base_currency.to_s.upcase
    alt_currency_code = base_currency_code == "VES" ? "USD" : "VES"

    {
      currency: debt_currency,
      total: totals[:total].to_d,
      paid: totals[:paid].to_d,
      balance: totals[:balance].to_d,
      total_base: convert_sale_amount(totals[:total], from_currency: debt_currency, to_currency: base_currency_code,
                                                      rate: rate),
      paid_base: convert_sale_amount(totals[:paid], from_currency: debt_currency, to_currency: base_currency_code,
                                                    rate: rate),
      balance_base: convert_sale_amount(totals[:balance], from_currency: debt_currency,
                                                          to_currency: base_currency_code, rate: rate),
      total_alt: convert_sale_amount(totals[:total], from_currency: debt_currency, to_currency: alt_currency_code,
                                                     rate: rate),
      paid_alt: convert_sale_amount(totals[:paid], from_currency: debt_currency, to_currency: alt_currency_code,
                                                   rate: rate),
      balance_alt: convert_sale_amount(totals[:balance], from_currency: debt_currency,
                                                         to_currency: alt_currency_code, rate: rate),
    }
  end

  def convert_sale_amount(amount, from_currency:, to_currency:, rate:)
    source_currency = from_currency.to_s.upcase
    target_currency = to_currency.to_s.upcase
    value = amount.to_d
    return value.round(2) if source_currency == target_currency

    normalized_rate = rate.to_d
    return nil unless normalized_rate.positive?

    usd_aliases = %w[USD USDT]

    return (value / normalized_rate).round(2) if source_currency == "VES" && usd_aliases.include?(target_currency)

    return (value * normalized_rate).round(2) if usd_aliases.include?(source_currency) && target_currency == "VES"

    nil
  end

  def create_receivable_debt_for_sale!(venta:, amount:, currency:, due_on: nil)
    issued_on = Time.use_zone("America/Caracas") { Time.zone.today }

    current_business.debts.create!(
      name: "Saldo venta ##{venta.id}",
      description: "Saldo pendiente venta ##{venta.id} [VENTA:#{venta.id}]",
      debt_kind: "receivable",
      amount: amount.to_d.round(2),
      currency: currency.to_s.upcase,
      issued_on: issued_on,
      due_on: due_on,
      cliente: venta.cliente,
    )
  end

  def default_method_for_account(account)
    return "" unless account

    case account.account_type
    when "cash_box"
      "cash"
    when "card"
      "card"
    when "digital_wallet"
      "wallet"
    when "crypto_wallet"
      "crypto"
    else
      ""
    end
  end
end
