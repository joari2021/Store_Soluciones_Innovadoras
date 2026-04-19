class VentasController < ApplicationController
  POS_CATALOG_ITEMS_PER_PAGE = 24

  helper_method :sale_deletable_by_current_user?, :checkout_discount_payload_for_sale

  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :set_venta, only: %i[destroy]
  before_action :authorize_destroy_sale!, only: %i[destroy]
  before_action :set_draft_venta, only: %i[show_draft update_draft destroy_draft borrador destroy_borrador]

  def index
    products_scope = ventas_products_scope
    @productos_total_count = products_scope.except(:includes, :order).count
    @productos = paginate_scope(products_scope, page: 1, items: POS_CATALOG_ITEMS_PER_PAGE)
    @products_next_page = next_page_for(total_count: @productos_total_count, page: 1, items: POS_CATALOG_ITEMS_PER_PAGE)

    @product_categories = current_business.productos
                                          .joins(:categoria)
                                          .group("categorias.nombre")
                                          .count
                                          .sort_by { |nombre, _cantidad| nombre.to_s.downcase }

    @accounts = current_business.accounts
                                .with_attached_payment_method_image
                                .with_attached_logo
                                .with_attached_small_logo
                                .where(active: true)
                                .where.not(account_type: "cash_box", cash_role: "cash_deposit")
                                .order(:name)
    @open_cash_shift = current_business.cash_shifts.open.includes(:opened_by).first
    @last_closed_cash_shift = current_business.cash_shifts.closed.first
    @open_shift_balance_checks_payload = open_shift_balance_checks_payload

    @products_payload = build_products_payload(@productos)

    @products_payload_by_id = @products_payload.index_by { |row| row[:id] }

    services_count_scope = current_business.services
                                           .where(available: true)
                                           .visible_for_user(Current.user)
    @services_total_count = services_count_scope.count
    @services = []
    @services_next_page = @services_total_count.positive? ? 1 : nil
    @services_preloaded = false

    @service_systems = services_count_scope
      .joins(:system_service)
      .group("system_services.name")
      .count
      .sort_by { |nombre, _cantidad| nombre.to_s.downcase }

    @services_payload = []
    @services_payload_by_id = {}

    @accounts_payload = @accounts.map do |account|
      {
        id: account.id,
        name: account.name,
        display_name: account.name_with_cash_role,
        account_type: account.account_type,
        cash_role: account.cash_role,
        currency: account.currency,
        currency_symbol: account.currency_symbol,
        balance: account.balance.to_d.to_f,
        is_bank: account.account_type == "bank_account",
        is_primary: account.is_primary,
        cashea_line_mode: account.cashea_line_mode,
        cashea_cotidiana_installments: account.cashea_cotidiana_installments,
        cashea_min_purchase_usd: account.cashea_min_purchase_usd.to_d.to_f,
        payment_method_image_url: (url_for(account.payment_method_image) if account.payment_method_image.attached?),
        small_logo_url: (url_for(account.small_logo) if account.small_logo.attached?),
        logo_url: (url_for(account.logo) if account.logo.attached?),
      }
    end

    @cash_box_accounts_payload = current_business.accounts
                                                 .where(account_type: "cash_box", currency: "VES")
                                                 .order(:cash_role, :name)
                                                 .map do |account|
      {
        id: account.id,
        name: account.name_with_cash_role,
        account_type: account.account_type,
        cash_role: account.cash_role,
        currency: account.currency,
        currency_symbol: account.currency_symbol,
        balance: account.balance.to_d.to_f,
      }
    end

    @drafts_payload = drafts_payload
  end

  def catalog_products
    page = params[:page].to_i
    page = 1 if page < 1

    scope = ventas_products_scope
    total_count = scope.count
    productos = paginate_scope(scope, page: page, items: POS_CATALOG_ITEMS_PER_PAGE)
    payload = build_products_payload(productos)
    payload_by_id = payload.index_by { |row| row[:id] }

    cards_html = render_to_string(
      partial: "ventas/catalog_product_card",
      collection: productos,
      as: :producto,
      formats: [:html],
      locals: {
        products_payload_by_id: payload_by_id,
        bcv_rate: current_bcv_rate_for_sales,
      },
    )

    render json: {
      cards_html: cards_html,
      products: payload,
      current_page: page,
      next_page: next_page_for(total_count: total_count, page: page, items: POS_CATALOG_ITEMS_PER_PAGE),
      total_count: total_count,
    }
  end

  def catalog_services
    page = params[:page].to_i
    page = 1 if page < 1

    tasa_dolar = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : nil
    unidad_vi = @unidad_VI.is_a?(Numeric) ? @unidad_VI.to_d : nil
    effective_bcv_rate = tasa_dolar.to_d.positive? ? tasa_dolar.to_d : TasaCambio.latest_value("Dolar BCV").to_d

    scope = ventas_services_scope
    total_count = scope.count
    services = paginate_scope(scope, page: page, items: POS_CATALOG_ITEMS_PER_PAGE)
    payload = build_services_payload(
      services,
      tasa_dolar: tasa_dolar,
      unidad_vi: unidad_vi,
      effective_bcv_rate: effective_bcv_rate,
    )
    payload_by_id = payload.index_by { |row| row[:id] }

    cards_html = render_to_string(
      partial: "ventas/catalog_service_card",
      collection: services,
      as: :service,
      formats: [:html],
      locals: {
        services_payload_by_id: payload_by_id,
        bcv_rate: current_bcv_rate_for_sales,
        unidad_vi: @unidad_VI,
      },
    )

    render json: {
      cards_html: cards_html,
      services: payload,
      current_page: page,
      next_page: next_page_for(total_count: total_count, page: page, items: POS_CATALOG_ITEMS_PER_PAGE),
      total_count: total_count,
    }
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

  def services_snapshot
    ids = params[:ids].to_s.split(",").map { |value| value.to_s.strip }.reject(&:blank?).uniq
    return render json: { services: [] } if ids.empty?

    tasa_dolar = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : nil
    unidad_vi = @unidad_VI.is_a?(Numeric) ? @unidad_VI.to_d : nil
    effective_bcv_rate = tasa_dolar.to_d.positive? ? tasa_dolar.to_d : TasaCambio.latest_value("Dolar BCV").to_d

    services = ventas_services_scope.where(id: ids)
    payload = build_services_payload(
      services,
      tasa_dolar: tasa_dolar,
      unidad_vi: unidad_vi,
      effective_bcv_rate: effective_bcv_rate,
    )

    render json: { services: payload }
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
    destroy_draft_record!(@draft_venta)

    render json: {
      success: true,
      drafts: drafts_payload,
      products: products_payload_for_business,
    }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message.presence || "No se pudo eliminar el borrador." }, status: :unprocessable_entity
  end

  def borradores
    @drafts = current_business
      .ventas
      .where(status: "draft")
      .includes(:cliente, :user, :venta_items)
      .order(updated_at: :desc)
  end

  def borrador
    @draft = @draft_venta
    @draft_items = @draft
      .venta_items
      .includes(:producto, :product_variation)
      .order(:id)
  end

  def destroy_borrador
    destroy_draft_record!(@draft_venta)

    redirect_to borradores_ventas_path, notice: "Borrador eliminado correctamente."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to borradores_ventas_path, alert: e.message.presence || "No se pudo eliminar el borrador."
  end

  def historial
    @cash_shifts_for_filter = current_business.cash_shifts.order(opened_at: :desc).limit(10)

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
    load_historial_cash_exchanges!
  end

  def show
    @venta = current_business
      .ventas
      .includes(:cliente, :user, venta_items: %i[producto product_variation], venta_payments: :account)
      .find(params[:id])

    @sale_reference = SaleCurrencyReferenceService.new([@venta]).totals_by_sale_id[@venta.id] || {}
    load_sale_credit_context!
    @sale_item_masked_names = sale_item_masked_names_for_view(@venta)
    @sale_item_discounts = sale_item_discounts_payload(@venta)
    load_sale_service_cost_breakdown_context!
  end

  def delivery_note
    @venta = current_business
      .ventas
      .includes(:cliente, :user, venta_items: %i[producto product_variation])
      .find(params[:id])

    if @venta.vat_mode != "none"
      return redirect_to venta_path(@venta), alert: "La nota de entrega solo puede generarse para facturas sin IVA."
    end

    @sale_reference = SaleCurrencyReferenceService.new([@venta]).totals_by_sale_id[@venta.id] || {}
    @sale_item_masked_names = sale_item_masked_names_for_view(@venta)
    @sale_item_discounts = sale_item_discounts_payload(@venta)
    load_sale_service_cost_breakdown_context!
    @business = current_business
    @delivery_print_date = Time.current
    @print_title = "Nota de Entrega Nro-#{@venta.id}"

    render :delivery_note, layout: "print"
  end

  def resumen_modal
    venta = current_business.ventas.includes(:cliente, :venta_items).find_by(id: params[:id])

    if venta.nil?
      render html: "<p class='text-sm text-rose-600'>No se encontró la venta solicitada.</p>".html_safe, status: :not_found
      return
    end

    render partial: 'ventas/venta_resumen_modal', locals: { venta: venta }
  end

  def destroy
    Venta.transaction do
      restore_stock_for_sale!(@venta)
      delete_account_movements_for_sale!(@venta)
      delete_service_cost_debts_for_sale!(@venta)
      delete_receivable_debts_for_sale!(@venta)
      @venta.destroy!
    end

    redirect_to historial_ventas_path,
                notice: "Venta eliminada exitosamente junto con sus registros asociados."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to historial_ventas_path,
                alert: e.message.presence || "No se pudo eliminar la venta."
  end

  def sale_deletable_by_current_user?(sale)
    return true if current_user_admin?

    return false if sale.blank?
    return false unless sale.cash_shift&.open?

    sale.user_id == Current.user&.id
  end

  def checkout_discount_payload_for_sale(sale)
    return nil if sale.blank?

    notes_payload = parse_notes_payload(sale.notes)
    raw_discount = notes_payload["checkout_discount"]
    return nil unless raw_discount.is_a?(Hash)

    amount = raw_discount["amount"].to_d
    return nil unless amount.positive?

    reason = raw_discount["reason"].to_s.strip
    reason_label = case reason
      when "exoneracion_de_faltante"
        "Exoneracion de faltante"
      when "oferta_por_compra"
        "Oferta por compra"
      else
        reason.humanize.presence || "Motivo no indicado"
      end

    {
      amount: amount.round(2),
      currency: raw_discount["currency"].to_s.upcase.presence || sale.base_currency,
      reason: reason,
      reason_label: reason_label,
    }
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
    client_totals = parsed_totals_payload(payload[:totals])
    raw_change = payload[:change]
    change_entries = if raw_change.is_a?(Array)
        raw_change
      elsif raw_change.present?
        [raw_change]
      else
        []
      end
    credit_sale = normalize_credit_sale_payload(payload[:credit_sale])
    cashea_sale = normalize_cashea_sale_payload(payload[:cashea])
    checkout_discount = normalize_checkout_discount_payload(payload[:checkout_discount])
    credit_sale_due_on = parse_payment_date(credit_sale[:due_on])
    service_cost_payment_entries = Array(payload[:service_cost_payments])
    if credit_sale[:due_on].present? && credit_sale_due_on.blank?
      return render json: { error: "La fecha de vencimiento del credito es invalida." },
                    status: :unprocessable_entity
    end

    if cashea_sale[:enabled]
      cashea_account = current_business.accounts.find_by(id: cashea_sale[:account_id])
      if cashea_account.blank? || !cashea_account.cashea_account?
        return render json: { error: "La cuenta Cashea seleccionada no es valida." }, status: :unprocessable_entity
      end

      cashea_sale[:account] = cashea_account
      cashea_sale[:line_mode] = cashea_account.cashea_line_mode
      cashea_sale[:installments] = cashea_account.cashea_installments_count
      cashea_sale[:custom_installments] = normalize_cashea_installments_payload(payload[:cashea])

      if cashea_sale[:initial_usd].to_d <= 0
        return render json: { error: "El monto inicial de Cashea debe ser mayor a 0." }, status: :unprocessable_entity
      end
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

    seller_user = source_draft&.user || Current.user

    venta = current_business.ventas.new(
      status: "draft",
      vat_mode: vat_mode,
      vat_rate: vat_rate,
      tasa_dolar: tasa_dolar,
      base_currency: base_currency,
      cash_shift: open_cash_shift,
      user: seller_user,
    )

    if payload[:cliente_id].present?
      cliente = current_business.clientes.find_by(id: payload[:cliente_id])
      venta.cliente = cliente if cliente
    end

    client_benefits = normalized_client_benefits_config(venta.cliente)

    service_item_rows = []

    items.each do |item|
      item_type = item[:item_type].to_s
      if item_type == "service" || item[:service_id].present?
        service_id = item[:service_id]
        service = current_business
          .services
          .includes(:system_service,
                    :service_print_coverage_prices,
                    :service_print_material_surcharges,
                    service_expense_structures: %i[service_product_expenses])
          .find_by(id: service_id)
        next unless service

        quantity = parse_decimal(item[:quantity], default: 0)
        next unless quantity.positive?

        recarga_pricing = if recarga_service?(service)
            resolve_recarga_pricing(
              service: service,
              payload: item,
              tasa_dolar: tasa_dolar,
              base_currency: base_currency,
            )
          else
            nil
          end

        if recarga_pricing&.dig(:error).present?
          return render json: { error: recarga_pricing[:error] }, status: :unprocessable_entity
        end

        unit_price_usd = if recarga_pricing.present?
            recarga_pricing[:unit_price_usd]
          elsif service.to_agree?
            parse_decimal(item[:unit_price_usd], default: 0)
          else
            service_unit_price_usd(service, tasa_dolar)
          end

        unit_price_base_amount = if recarga_pricing.present?
            recarga_pricing[:unit_price_base_amount].to_d
          else
            parse_decimal(item[:unit_price_base_amount], default: 0).round(2)
          end
        unit_price_base_currency = if recarga_pricing.present?
            normalize_currency(recarga_pricing[:unit_price_base_currency],
                               default: base_currency)
          else
            normalize_currency(item[:unit_price_base_currency], default: base_currency)
          end

        unit_price_usd, unit_price_base_amount, discount_percent = apply_printing_discount_pricing(
          service: service,
          payload: item,
          unit_price_usd: unit_price_usd,
          unit_price_base_amount: unit_price_base_amount,
          tasa_dolar: tasa_dolar,
          base_currency: base_currency,
        )

        client_service_price_usd = client_service_fixed_price_usd(
          benefits_config: client_benefits,
          service_id: service.id,
        )
        if client_service_price_usd.positive?
          unit_price_usd = client_service_price_usd
          unit_price_base_amount = if base_currency == "VES" && tasa_dolar.to_d.positive?
              (client_service_price_usd * tasa_dolar.to_d).round(2)
            else
              client_service_price_usd.round(2)
            end
          discount_percent = 0.to_d
        end

        service_discount_rules = active_discount_rules_by_target(:services)[service.id]

        base_unit_price_base_amount_for_schedule = unit_price_base_amount.to_d
        if !base_unit_price_base_amount_for_schedule.positive? && service_uses_ves_reference_pricing?(service)
          base_unit_price_base_amount_for_schedule = service.unit_price_bs(
            tasa_dolar: tasa_dolar,
            unidad_vi: parse_decimal(@unidad_VI, default: 0),
          ).to_d
        end

        unit_price_usd = apply_discount_schedule_to_unit_price_usd(
          base_unit_price_usd: unit_price_usd,
          quantity: quantity,
          rules: service_discount_rules,
          fixed_currency: service_discount_currency(service),
          tasa_dolar: tasa_dolar,
        )

        unit_price_base_amount = 0.to_d
        if base_currency == "VES" && service_uses_ves_reference_pricing?(service)
          unit_price_base_amount = apply_discount_schedule_to_unit_price_amount(
            base_unit_price_amount: base_unit_price_base_amount_for_schedule,
            quantity: quantity,
            rules: service_discount_rules,
            fixed_currency: service_discount_currency(service),
            target_currency: "VES",
            tasa_dolar: tasa_dolar,
          )
        elsif base_currency == "VES" && tasa_dolar.to_d.positive?
          unit_price_base_amount = (unit_price_usd.to_d * tasa_dolar.to_d).round(2)
        elsif base_currency == "USD"
          unit_price_base_amount = unit_price_usd.to_d.round(2)
        end

        unit_price_usd /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive?
        if unit_price_base_amount.positive? && vat_mode == "included" && vat_rate.positive?
          unit_price_base_amount /= (1 + vat_rate)
        end

        if unit_price_usd.nil? || unit_price_usd.to_d <= 0
          message = service.to_agree? ? "Debes indicar el precio acordado del servicio." : "No se pudo calcular el precio del servicio."
          return render json: { error: message }, status: :unprocessable_entity
        end

        line_subtotal = (unit_price_usd.to_d * quantity.to_d).round(2)

        venta.venta_items.build(
          product_name: service_sale_display_name(service: service, payload: item),
          variation_name: service.system_service&.name.presence || "Servicio",
          quantity: quantity,
          unit_price_usd: unit_price_usd,
          subtotal_usd: line_subtotal,
          unit_price_base_amount: (unit_price_base_amount.positive? ? unit_price_base_amount : nil),
          unit_price_base_currency: unit_price_base_currency,
        )

        service_item_rows << {
          service: service,
          quantity: quantity,
          payload: item.to_h,
          recarga_pricing: recarga_pricing,
          printing_discount_percent: discount_percent,
        }
        next
      end

      product_id = item[:product_id]
      product = current_business.productos.includes(:product_variations).find_by(id: product_id)
      next unless product

      product_exento = product.respond_to?(:exento?) ? product.exento? : false

      quantity = parse_decimal(item[:quantity], default: 0)
      next unless quantity.positive?

      variation = (product.product_variations.find_by(id: item[:variation_id]) if item[:variation_id].present?)
      variation ||= product.product_variations.order(:id).first
      next unless variation

      unit_price = client_product_unit_price_usd(
        product: product,
        benefits_config: client_benefits,
      )

      unit_price = apply_discount_schedule_to_unit_price_usd(
        base_unit_price_usd: unit_price,
        quantity: quantity,
        rules: active_discount_rules_by_target(:products)[product.id],
        fixed_currency: 'USD',
        tasa_dolar: tasa_dolar,
      )

      unit_price /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive? && !product_exento
      line_subtotal = (unit_price.to_d * quantity.to_d).round(2)
      product_unit_base_amount = 0.to_d
      if base_currency == "VES" && tasa_dolar.to_d.positive?
        product_unit_base_amount = (unit_price.to_d * tasa_dolar.to_d).round(2)
      elsif base_currency == "USD"
        product_unit_base_amount = unit_price.to_d.round(2)
      end

      product_item_attrs = {
        producto: product,
        product_variation: variation,
        quantity: quantity,
        unit_price_usd: unit_price,
        subtotal_usd: line_subtotal,
        unit_price_base_amount: (product_unit_base_amount.positive? ? product_unit_base_amount : nil),
        unit_price_base_currency: base_currency,
      }
      product_item_attrs[:exento] = product_exento if VentaItem.column_names.include?("exento")

      venta.venta_items.build(product_item_attrs)
    end

    if venta.venta_items.empty?
      return render json: { error: "No hay items validos en la venta." }, status: :unprocessable_entity
    end

    venta.valid?
    server_totals = calculated_sale_totals_for(venta)

    if client_totals.present?
      totals_mismatch_message = validate_client_totals_against_server(
        client_totals: client_totals,
        server_totals: server_totals,
        tolerance: 0.05.to_d,
      )
      if totals_mismatch_message.present?
        return render json: { error: totals_mismatch_message }, status: :unprocessable_entity
      end
    end

    recarga_entries = recarga_debit_entries(service_item_rows)
    if recarga_entries.any?
      account = payall_account
      return render json: { error: "No existe una cuenta Payall." }, status: :unprocessable_entity if account.blank?

      if source_draft.blank?
        recarga_total = recarga_entries.sum { |row| row[:amount].to_d }
        if recarga_total > account.balance.to_d
          return render json: { error: "Saldo insuficiente en Payall para registrar la recarga." },
                        status: :unprocessable_entity
        end
      end
    end

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

      if account.account_type == "cash_box" && account.cash_role == "cash_deposit"
        return render json: { error: "No puedes registrar ventas en cuentas de deposito." },
                      status: :unprocessable_entity
      end

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
          return render json: { error: "La referencia debe tener 4 digitos." }, status: :unprocessable_entity
        end

        if payment_date.blank?
          return render json: { error: "Debes indicar la fecha del pago para cuentas bancarias." },
                        status: :unprocessable_entity
        end

        amount_signature = raw_amount.to_d.round(2)
        duplicate_key = [account.id, payment_date.iso8601, amount_signature.to_s("F"), reference].join("|")
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
          reference: reference,
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
      if change_account.account_type == "cash_box" && change_account.cash_role == "cash_deposit"
        return render json: { error: "No puedes registrar vuelto en cuentas de deposito." },
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
          return render json: { error: "La referencia del vuelto debe tener 4 digitos." }, status: :unprocessable_entity
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
    total_due = total_due_in_currency(venta, comparison_currency, tasa_dolar, calculated_totals: server_totals)

    if cashea_sale[:enabled] && credit_sale[:enabled]
      return render json: { error: "Cashea no permite registrar saldo pendiente manual en el checkout." },
                    status: :unprocessable_entity
    end

    discount_amount = 0.to_d
    if cashea_sale[:enabled] && checkout_discount[:enabled]
      return render json: { error: "Cashea no permite aplicar descuento en el checkout." }, status: :unprocessable_entity
    end

    if checkout_discount[:enabled]
      if checkout_discount[:reason].blank?
        return render json: { error: "Selecciona un motivo de descuento valido." }, status: :unprocessable_entity
      end

      discount_amount = convert_checkout_discount_to_currency(
        amount: checkout_discount[:amount],
        from_currency: base_currency,
        to_currency: comparison_currency,
        tasa_dolar: tasa_dolar,
      )
      if discount_amount.nil?
        return render json: { error: "No se pudo convertir el descuento al total de la venta." }, status: :unprocessable_entity
      end

      if discount_amount <= 0
        return render json: { error: "El monto del descuento debe ser mayor a cero." }, status: :unprocessable_entity
      end

      if discount_amount > total_due
        return render json: { error: "El descuento no puede ser mayor al total de la venta." }, status: :unprocessable_entity
      end
    end

    total_due = (total_due - discount_amount).round(2)
    total_due = 0.to_d if total_due.negative?
    paid_total = 0.to_d

    payment_rows.each do |row|
      converted = convert_payment_to_currency(row[:amount_original], row[:currency], comparison_currency, tasa_dolar)
      if converted.nil?
        return render json: { error: "Tasa dolar no disponible para convertir pagos." },
                      status: :unprocessable_entity
      end
      paid_total += converted
    end

    if cashea_sale[:enabled]
      total_due_usd = convert_payment_to_currency(total_due, comparison_currency, "USD", tasa_dolar)
      if total_due_usd.nil?
        return render json: { error: "No se pudo convertir el total de la venta a USD para validar Cashea." },
                      status: :unprocessable_entity
      end

      minimum_purchase_usd = cashea_sale[:account].cashea_min_purchase_usd.to_d
      if minimum_purchase_usd.positive? && total_due_usd < minimum_purchase_usd
        return render json: { error: "La venta no alcanza la compra minima de Cashea (#{minimum_purchase_usd.to_s('F')} USD)." },
                      status: :unprocessable_entity
      end
    end

    tolerance = 0.01
    delta = (paid_total - total_due).round(2)

    cashea_initial_amount = 0.to_d
    cashea_financing_enabled = false
    if cashea_sale[:enabled]
      converted_initial = convert_payment_to_currency(cashea_sale[:initial_usd], "USD", comparison_currency, tasa_dolar)
      if converted_initial.nil?
        return render json: { error: "No se pudo convertir el inicial de Cashea con la tasa actual." },
                      status: :unprocessable_entity
      end

      cashea_initial_amount = converted_initial.round(2)
      if cashea_initial_amount > total_due
        return render json: { error: "El inicial de Cashea no puede superar el total de la venta." },
                      status: :unprocessable_entity
      end

      initial_delta = (paid_total - cashea_initial_amount).round(2)
      if initial_delta < -tolerance
        return render json: { error: "Falta por cancelar #{initial_delta.abs.round(2)} #{comparison_currency} del inicial Cashea." },
                      status: :unprocessable_entity
      end

      remaining_credit_amount = (total_due - cashea_initial_amount).round(2)
      remaining_credit_amount = 0.to_d if remaining_credit_amount.negative?
      cashea_financing_enabled = remaining_credit_amount.positive?
    else
      remaining_credit_amount = delta < -tolerance ? delta.abs.round(2) : 0.to_d
    end

    if remaining_credit_amount.positive? && !credit_sale[:enabled] && !cashea_financing_enabled
      return render json: { error: "Falta por cancelar #{remaining_credit_amount} #{comparison_currency}." },
                    status: :unprocessable_entity
    end

    if remaining_credit_amount.positive? && venta.cliente.blank?
      return render json: { error: "Debes seleccionar un cliente para registrar saldo en deuda por cobrar." },
                    status: :unprocessable_entity
    end

    if remaining_credit_amount.positive? && venta.cliente.present? && venta.cliente.phone.to_s.strip.blank?
      return render json: { error: "El cliente registrado no posee numero de telefono, ese dato es obligatorio." },
                    status: :unprocessable_entity
    end

    # Vuelto es opcional; no se valida contra el delta.

    payment_rows.each { |row| venta.venta_payments.build(row) }
    change_rows.each { |row| venta.venta_payments.build(row) }

    if cashea_sale[:enabled] && payment_rows.empty?
      return render json: { error: "Debes registrar al menos un metodo de pago para el inicial de Cashea." },
                    status: :unprocessable_entity
    end

    if payment_rows.empty? && !remaining_credit_amount.positive?
      return render json: { error: "Debes registrar al menos un metodo de pago." }, status: :unprocessable_entity
    end

    venta.status = "paid"

    begin
      Venta.transaction do
        if source_draft
          restore_stock_for_sale!(source_draft, strict: false)
          relabel_payall_draft_movements!(source_draft, venta)
          source_draft.destroy!
        end

        venta.save!

        if source_draft.blank? && recarga_entries.any?
          payall = payall_account
          recarga_entries.each do |entry|
            amount = entry[:amount].to_d
            next unless amount.positive?

            service_name = entry[:service]&.description.to_s.strip.presence || "Recarga"
            payall.account_movements.create!(
              movement_kind: "expense",
              amount: amount,
              description: "Recarga Payall #{service_name} [VENTA:#{venta.id}]",
              occurred_at: Time.current,
            )
          end
        end

        consumed_product_lots = reserve_product_stock_for_sale!(venta)
        reserved_service_products = reserve_service_product_expenses_for_items!(service_item_rows, venta: venta)
        notes_payload = parse_notes_payload(venta.notes)
        notes_payload.delete("draft_state")
        notes_payload["reserved_product_items"] = reserved_product_items_payload_for_sale(venta)
        notes_payload["product_lot_consumptions"] = consumed_product_lots
        notes_payload["reserved_service_products"] = reserved_service_products
        notes_payload["service_cost_settlements"] = service_cost_settlements_payload_for_notes(service_cost_settlements)
        notes_payload["sold_service_parties"] = sold_service_parties_payload_for_notes(service_item_rows)
        notes_payload["sold_service_printings"] = sold_service_printings_payload_for_notes(
          service_item_rows: service_item_rows,
          tasa_dolar: tasa_dolar,
        )
        discount_payload = service_item_discounts_payload_for_sale(venta: venta, service_item_rows: service_item_rows)
        notes_payload["service_item_discounts"] = discount_payload if discount_payload.present?
        if checkout_discount[:enabled]
          notes_payload["checkout_discount"] = {
            "amount" => checkout_discount[:amount].to_d.round(2).to_f,
            "currency" => base_currency,
            "reason" => checkout_discount[:reason],
          }
        else
          notes_payload.delete("checkout_discount")
        end
        venta.update!(notes: serialize_notes_payload(notes_payload))

        payment_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account
          supports_movement_reference = AccountMovement.column_names.include?("reference")
          movement_occurred_at = account_movement_occurred_at_from_payment_date(row[:payment_date])

          movement_attrs = {
            movement_kind: "income",
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, "Ingreso"),
            occurred_at: movement_occurred_at,
          }
          if account.account_type == "bank_account" && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          if supports_movement_reference && row[:reference].present?
            movement_attrs[:reference] = row[:reference].presence
          end

          account.account_movements.create!(movement_attrs)
        end

        change_rows.each do |row|
          account = current_business.accounts.find_by(id: row[:account_id])
          next unless account
          supports_movement_reference = AccountMovement.column_names.include?("reference")

          movement_attrs = {
            movement_kind: "expense",
            amount: row[:amount_original].to_d,
            description: build_movement_description(venta, row, "Vuelto"),
            occurred_at: Time.current,
          }
          if account.account_type == "bank_account" && %w[transfer mobile].include?(row[:payment_method])
            movement_attrs[:payment_method] = normalize_account_movement_method(row[:payment_method])
          end

          if supports_movement_reference && row[:reference].present?
            movement_attrs[:reference] = row[:reference].presence
          end

          account.account_movements.create!(movement_attrs)

          next unless account.account_type == "bank_account" && row[:payment_method] == "mobile"

          commission_amount = (row[:amount_original].to_d * 0.003).round(2)
          next unless commission_amount.positive?

          commission_attrs = {
            movement_kind: "expense",
            amount: commission_amount,
            description: build_movement_description(venta, row, "Comision pago movil"),
            occurred_at: movement_occurred_at,
            payment_method: normalize_account_movement_method("mobile"),
          }
          if supports_movement_reference && row[:reference].present?
            commission_attrs[:reference] = row[:reference].presence
          end
          account.account_movements.create!(commission_attrs)
        end

        register_service_cost_settlements_for_sale!(
          venta: venta,
          settlements: service_cost_settlements,
        )

        if remaining_credit_amount.positive?
          debt_amount_usd = convert_payment_to_currency(
            remaining_credit_amount,
            comparison_currency,
            "USD",
            tasa_dolar,
          )
          if debt_amount_usd.nil?
            venta.errors.add(:base, "No se pudo convertir el saldo pendiente a USD para generar la deuda.")
            raise ActiveRecord::RecordInvalid.new(venta)
          end

          if cashea_financing_enabled
            custom_installments = Array(cashea_sale[:custom_installments])
            if custom_installments.any?
              expected_installments = cashea_sale[:installments].to_i
              if expected_installments <= 0
                venta.errors.add(:base, "La cuenta Cashea no tiene un numero valido de cuotas.")
                raise ActiveRecord::RecordInvalid.new(venta)
              end

              if custom_installments.size != expected_installments
                venta.errors.add(:base, "Debes configurar exactamente #{expected_installments} cuotas Cashea.")
                raise ActiveRecord::RecordInvalid.new(venta)
              end

              if custom_installments.any? { |row| row[:amount_usd].to_d <= 0 || row[:due_on].blank? }
                venta.errors.add(:base, "Cada cuota Cashea debe tener monto y fecha de vencimiento validos.")
                raise ActiveRecord::RecordInvalid.new(venta)
              end

              custom_total = custom_installments.sum { |row| row[:amount_usd].to_d }.round(2)
              if (custom_total - debt_amount_usd.to_d.round(2)).abs > 0.01.to_d
                venta.errors.add(:base, "La suma de cuotas Cashea (#{custom_total.to_s('F')} USD) debe coincidir con el saldo financiado (#{debt_amount_usd.to_d.round(2).to_s('F')} USD).")
                raise ActiveRecord::RecordInvalid.new(venta)
              end
            end

            create_cashea_receivable_installments_for_sale!(
              venta: venta,
              account: cashea_sale[:account],
              total_amount_usd: debt_amount_usd,
              first_due_on: credit_sale_due_on,
              custom_installments: custom_installments,
            )
          else
            create_receivable_debt_for_sale!(
              venta: venta,
              amount: debt_amount_usd,
              currency: "USD",
              due_on: credit_sale_due_on,
            )
          end
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
      .find_by(id: params[:id])

    return if @draft_venta.present?

    json_draft_request = request.format.json? || request.path.to_s.include?("/ventas/drafts/")

    if json_draft_request
      render json: { error: "Borrador no encontrado." }, status: :not_found
      return
    end

    respond_to do |format|
      format.html { redirect_to borradores_ventas_path, alert: "El borrador no existe o ya fue eliminado." }
      format.any { head :not_found }
    end
  end

  def authorize_destroy_sale!
    return if sale_deletable_by_current_user?(@venta)

    redirect_to historial_ventas_path,
                alert: "Solo puedes eliminar ventas de turnos abiertos facturadas por ti."
  end

  def destroy_draft_record!(draft)
    Venta.transaction do
      restore_stock_for_sale!(draft, strict: false)
      delete_payall_draft_movements!(draft)
      draft.destroy!
    end
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
    unless params.key?(:cash_shift_id)
      latest_shift_id = current_business.cash_shifts.order(opened_at: :desc).limit(1).pick(:id)
      @selected_cash_shift_id = latest_shift_id.to_s if latest_shift_id.present?
    end
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

    filtered_scope = scope.where.not(status: "draft")

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

  def account_movement_occurred_at_from_payment_date(payment_date)
    caracas_now = Time.current.in_time_zone("America/Caracas")
    return caracas_now if payment_date.blank?

    caracas_now.change(year: payment_date.year, month: payment_date.month, day: payment_date.day)
  end

  def find_duplicate_bank_payment(account_id:, payment_date:, amount_original:, reference:)
    return nil if account_id.blank? || payment_date.blank? || reference.blank?

    normalized_amount = amount_original.to_d.round(2)
    return nil unless normalized_amount.positive?

    VentaPayment
      .joins(:venta)
      .where(
        account_id: account_id,
        payment_kind: "in",
        payment_date: payment_date,
        amount_original: normalized_amount,
        reference: reference,
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
    reference = existing_payment&.reference.to_s.strip

    {
      account_id: account.id,
      account_name: account.name,
      payment_date: date_label,
      amount: normalized_amount.to_s("F"),
      reference: reference,
      currency: account.currency,
      currency_symbol: account.currency_symbol,
      venta_id: venta_id,
      venta_url: venta_url,
      message: "Ya existe un pago registrado en #{account.name} con monto #{normalized_amount.to_s("F")} #{account.currency}, fecha #{date_label} y referencia #{reference}.",
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

  def load_historial_cash_exchanges!
    scope = current_business.cambio_efectivos.includes(:user).order(occurred_at: :desc)

    if @selected_cash_shift_id.present?
      scope = scope.where(cash_shift_id: @selected_cash_shift_id.to_i)
    end

    if @selected_fecha_desde.present?
      scope = scope.where("occurred_at >= ?", @selected_fecha_desde.in_time_zone.beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      scope = scope.where("occurred_at <= ?", @selected_fecha_hasta.in_time_zone.end_of_day)
    end

    @historial_cash_exchanges = scope.limit(50)
  end

  def restore_stock_for_sale!(venta, strict: true)
    restored_product_lot_quantities = restore_reserved_product_stock_from_notes!(venta, strict: strict)

    grouped_items = venta.venta_items
                         .select { |item| item.producto_id.present? && item.product_variation_id.present? }
                         .group_by { |item| [item.producto_id, item.product_variation_id] }

    grouped_items.each do |(producto_id, variation_id), items|
      quantity_units = items.sum { |item| item.quantity.to_d }
      quantity_units -= restored_product_lot_quantities.fetch([producto_id.to_i, variation_id.to_i], 0.to_d)
      next unless quantity_units.positive?

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
    end

    restore_reserved_service_stock_from_notes!(venta, strict: strict)
  end

  def restore_reserved_product_stock_from_notes!(venta, strict: true)
    notes_payload = parse_notes_payload(venta.notes)
    rows = Array(notes_payload["product_lot_consumptions"])
    restored_by_key = Hash.new(0.to_d)

    rows.each do |row|
      producto_id = row["product_id"] || row[:product_id]
      variation_id = row["variation_id"] || row[:variation_id]
      stock_lot_id = row["stock_lot_id"] || row[:stock_lot_id]
      quantity_units = parse_decimal(row["quantity"] || row[:quantity], default: 0)
      next if producto_id.blank? || variation_id.blank? || !quantity_units.positive?
      next if stock_lot_id.blank?

      restored_exact = restore_product_variation_units_in_lot!(
        producto_id: producto_id,
        variation_id: variation_id,
        stock_lot_id: stock_lot_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
      next unless restored_exact

      restored_by_key[[producto_id.to_i, variation_id.to_i]] += quantity_units.to_d
    end

    restored_by_key
  end

  def restore_product_variation_units!(producto_id:, variation_id:, quantity_units:, venta:, strict: true)
    producto = current_business.productos.find_by(id: producto_id)
    return unless producto

    remaining_to_restore = quantity_units.to_d

    producto.stock_lots.ordered_fifo.each do |lot|
      row = lot.variation_row_for(variation_id, create_if_missing: true)
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
    return unless strict

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

  def delete_receivable_debts_for_sale!(venta)
    debts_scope = current_business.debts.where(debt_kind: "receivable")

    debts_scope
      .where(venta_id: venta.id)
      .find_each(&:destroy!)

    pattern = "%[VENTA:#{venta.id}]%"
    debts_scope
      .where("description LIKE ?", pattern)
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
    draft.user = Current.user if draft.new_record? && draft.user.blank?
    requested_visibility = normalize_draft_visibility(payload[:draft_visibility], default: draft_visibility(draft))

    service_item_rows = []

    begin
      Venta.transaction do
        if draft.persisted?
          restore_stock_for_sale!(draft, strict: false)
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

        client_benefits = normalized_client_benefits_config(draft.cliente)

        items.each do |item|
          item_type = item[:item_type].to_s
          if item_type == "service" || item[:service_id].present?
            service = current_business
              .services
              .includes(:system_service,
                        :service_print_coverage_prices,
                        :service_print_material_surcharges,
                        service_expense_structures: %i[service_product_expenses])
              .find_by(id: item[:service_id])
            next unless service

            quantity = parse_decimal(item[:quantity], default: 0)
            next unless quantity.positive?

            recarga_pricing = if recarga_service?(service)
                resolve_recarga_pricing(
                  service: service,
                  payload: item,
                  tasa_dolar: tasa_dolar,
                  base_currency: base_currency,
                )
              else
                nil
              end

            if recarga_pricing&.dig(:error).present?
              raise ActiveRecord::RecordInvalid.new(draft), recarga_pricing[:error]
            end

            unit_price_usd = if recarga_pricing.present?
                recarga_pricing[:unit_price_usd]
              elsif service.to_agree?
                parse_decimal(item[:unit_price_usd], default: 0)
              else
                service_unit_price_usd(service, tasa_dolar)
              end

            unit_price_base_amount = if recarga_pricing.present?
                recarga_pricing[:unit_price_base_amount].to_d
              else
                parse_decimal(item[:unit_price_base_amount], default: 0).round(2)
              end

            unit_price_usd, unit_price_base_amount, discount_percent = apply_printing_discount_pricing(
              service: service,
              payload: item,
              unit_price_usd: unit_price_usd,
              unit_price_base_amount: unit_price_base_amount,
              tasa_dolar: tasa_dolar,
              base_currency: base_currency,
            )

            client_service_price_usd = client_service_fixed_price_usd(
              benefits_config: client_benefits,
              service_id: service.id,
            )
            if client_service_price_usd.positive?
              unit_price_usd = client_service_price_usd
              unit_price_base_amount = if base_currency == "VES" && tasa_dolar.to_d.positive?
                  (client_service_price_usd * tasa_dolar.to_d).round(2)
                else
                  client_service_price_usd.round(2)
                end
              discount_percent = 0.to_d
            end

            unit_price_usd = apply_discount_schedule_to_unit_price_usd(
              base_unit_price_usd: unit_price_usd,
              quantity: quantity,
              rules: active_discount_rules_by_target(:services)[service.id],
              fixed_currency: service_discount_currency(service),
              tasa_dolar: tasa_dolar,
            )

            unit_price_base_amount = 0.to_d
            if base_currency == "VES" && tasa_dolar.to_d.positive?
              unit_price_base_amount = (unit_price_usd.to_d * tasa_dolar.to_d).round(2)
            elsif base_currency == "USD"
              unit_price_base_amount = unit_price_usd.to_d.round(2)
            end

            unit_price_usd /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive?
            if unit_price_base_amount.positive? && vat_mode == "included" && vat_rate.positive?
              unit_price_base_amount /= (1 + vat_rate)
            end

            if unit_price_usd.nil? || unit_price_usd.to_d <= 0
              message = service.to_agree? ? "Debes indicar el precio acordado del servicio." : "No se pudo calcular el precio del servicio."
              raise ActiveRecord::RecordInvalid.new(draft), message
            end

            draft.venta_items.build(
              product_name: service_sale_display_name(service: service, payload: item),
              variation_name: service.system_service&.name.presence || "Servicio",
              quantity: quantity,
              unit_price_usd: unit_price_usd,
              unit_price_base_amount: (unit_price_base_amount.positive? ? unit_price_base_amount : nil),
              unit_price_base_currency: normalize_currency(
                recarga_pricing.present? ? recarga_pricing[:unit_price_base_currency] : item[:unit_price_base_currency],
                default: base_currency,
              ),
            )

            service_item_rows << {
              service: service,
              quantity: quantity,
              payload: item.to_h,
              recarga_pricing: recarga_pricing,
              printing_discount_percent: discount_percent,
            }

            next
          end

          product = current_business.productos.includes(:product_variations).find_by(id: item[:product_id])
          next unless product

          product_exento = product.respond_to?(:exento?) ? product.exento? : false

          quantity = parse_decimal(item[:quantity], default: 0)
          next unless quantity.positive?

          variation = (product.product_variations.find_by(id: item[:variation_id]) if item[:variation_id].present?)
          variation ||= product.product_variations.order(:id).first
          next unless variation

          unit_price = client_product_unit_price_usd(
            product: product,
            benefits_config: client_benefits,
          )

          unit_price = apply_discount_schedule_to_unit_price_usd(
            base_unit_price_usd: unit_price,
            quantity: quantity,
            rules: active_discount_rules_by_target(:products)[product.id],
            fixed_currency: 'USD',
            tasa_dolar: tasa_dolar,
          )

          unit_price /= (1 + vat_rate) if vat_mode == "included" && vat_rate.positive? && !product_exento
          product_unit_base_amount = 0.to_d
          if base_currency == "VES" && tasa_dolar.to_d.positive?
            product_unit_base_amount = (unit_price.to_d * tasa_dolar.to_d).round(2)
          elsif base_currency == "USD"
            product_unit_base_amount = unit_price.to_d.round(2)
          end

          draft_item_attrs = {
            producto: product,
            product_variation: variation,
            quantity: quantity,
            unit_price_usd: unit_price,
            unit_price_base_amount: (product_unit_base_amount.positive? ? product_unit_base_amount : nil),
            unit_price_base_currency: base_currency,
          }
          draft_item_attrs[:exento] = product_exento if VentaItem.column_names.include?("exento")

          draft.venta_items.build(draft_item_attrs)
        end

        if draft.venta_items.empty?
          raise ActiveRecord::RecordInvalid.new(draft), "No hay items validos para guardar el borrador."
        end

        recarga_entries = recarga_debit_entries(service_item_rows)
        if recarga_entries.any?
          account = payall_account
          raise ActiveRecord::RecordInvalid.new(draft), "No existe una cuenta Payall." if account.blank?

          available = account.balance.to_d
          available += payall_draft_reserved_total(draft) if draft.persisted?

          recarga_total = recarga_entries.sum { |row| row[:amount].to_d }
          if recarga_total > available
            raise ActiveRecord::RecordInvalid.new(draft), "Saldo insuficiente en Payall para registrar la recarga."
          end
        end

        draft.save!

        sync_payall_recarga_movements_for_draft!(draft, recarga_entries)

        consumed_product_lots = reserve_product_stock_for_sale!(draft)
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
        notes_payload["product_lot_consumptions"] = consumed_product_lots
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
    product_discount_rules = active_discount_rules_by_target(:products)

    productos.map do |producto|
      variation_rows = producto.stock_lot_variations.to_a
      variation_groups = variation_rows.group_by(&:product_variation_id)
      variation_totals = variation_groups.transform_values do |rows|
        rows.sum { |row| row.quantity_remaining.to_d }
      end

      # Compatibilidad: algunos lotes historicos o importaciones antiguas pueden
      # guardar stock con product_variation_id nil para productos que hoy tienen
      # una sola variacion activa (por ejemplo, "Unica"). En ese caso, atribuimos
      # ese stock a la unica variacion para que ventas lo reconozca correctamente.
      if producto.product_variations.size == 1
        unique_variation_id = producto.product_variations.first.id
        nil_variation_total = variation_totals[nil].to_d

        if nil_variation_total.positive?
          variation_totals[unique_variation_id] = variation_totals[unique_variation_id].to_d + nil_variation_total
          variation_totals.delete(nil)
        end
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
        exento: producto.respond_to?(:exento?) ? producto.exento? : false,
        available_total: total_units.to_f,
        variations: variations_payload,
        scheduled_discount_rules: serialize_discount_rules_for_front(
          product_discount_rules[producto.id],
          default_fixed_currency: 'USD',
          default_fixed_symbol: '$'
        ),
      }
    end
  end

  def build_services_payload(services, tasa_dolar:, unidad_vi:, effective_bcv_rate:)
    service_discount_rules = active_discount_rules_by_target(:services)
    reference_cache = {}
    symbol_cache = {}
    service_references = services.map do |service|
      reference = service.currency_base_price.to_s.strip.presence || Service::DEFAULT_REFERENCE
      reference == Service::LEGACY_USD_REFERENCE ? Service::DEFAULT_REFERENCE : reference
    end.uniq

    service_references.each do |reference|
      reference_cache[reference] = case reference
        when Service::BOLIVAR_REFERENCE
          1.to_d
        when Service::DEFAULT_REFERENCE
          effective_bcv_rate
        else
          TasaCambio.latest_value(reference).to_d
        end

      symbol_cache[reference] = TasaCambio.latest_symbol(reference).presence ||
                                TasaCambio::DEFAULT_SYMBOLS[reference] ||
                                (reference == Service::BOLIVAR_REFERENCE ? "Bs" : "$")
    end

    services.map do |service|
      system_service = service.system_service
      recarga_service = system_service&.recarga_system? || false
      unit_price_usd = service.fixed? ? service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi) : nil
      unit_price_bs = service.fixed? ? service.unit_price_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi) : nil
      unit_cost_usd = if service_cost_debit_enabled?(service)
          service.total_expense_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi, active_only: true)
        end
      currency_base_reference = service.currency_base_price.to_s.strip.presence || Service::DEFAULT_REFERENCE
      currency_base_reference = Service::DEFAULT_REFERENCE if currency_base_reference == Service::LEGACY_USD_REFERENCE

      reference_rate_bs = reference_cache[currency_base_reference]
      currency_symbol = symbol_cache[currency_base_reference]

      consumable_costs = []
      has_manager_or_variable_expense = false
      physical_printing_payload = build_service_physical_printing_payload(service: service,
                                                                          tasa_dolar: effective_bcv_rate)

      service.active_expense_structures_for_sales.each do |structure|
        has_manager_or_variable_expense ||= structure.service_manager_expenses.any?
        has_manager_or_variable_expense ||= structure.service_variable_expenses.any?
      end

      {
        id: service.id,
        name: service.description.to_s,
        sale_display_name: service.print_sale_display_name.to_s,
        system_name: system_service&.name.to_s,
        system_service_id: system_service&.id,
        system_service_image_url: (url_for(system_service.image) if system_service&.image&.attached?),
        recarga_image_url: (url_for(service.recarga_image) if service.recarga_image&.attached?),
        recarga_service: recarga_service,
        recarga_min_amount: service.recarga_min_amount.to_d.to_f,
        recarga_multiple_amount: service.recarga_multiple_amount.to_d.to_f,
        recarga_profit_percent: service.recarga_profit_percent.to_d.to_f,
        printing_type_service: service.printing_type_service?,
        lamination_type_service: service.lamination_type_service?,
        price_usd: unit_price_usd&.to_f,
        price_bs: unit_price_bs&.to_f,
        price_on_request: service.to_agree?,
        pricing_mode: service.pricing_mode,
        delivery_physical_enabled: service.delivery_physical_enabled?,
        delivery_digital_enabled: service.delivery_digital_enabled?,
        warn_digital_only_delivery_in_sales: service.warn_digital_only_delivery_in_sales?,
        cost_enabled: service.cost?,
        unit_cost_usd: unit_cost_usd&.to_f,
        currency_base_price: currency_base_reference,
        currency_symbol: currency_symbol,
        reference_rate_bs: reference_rate_bs.positive? ? reference_rate_bs.to_f : nil,
        has_manager_or_variable_expense: has_manager_or_variable_expense,
        physical_printing: physical_printing_payload,
        print_coverage_options: service.service_print_coverage_prices
          .sort_by { |row| [row.price_bs.to_d, row.coverage_percent.to_d, row.id.to_i] }
          .map do |row|
          {
            id: row.id,
            coverage_percent: row.coverage_percent.to_d.to_f,
            price_bs: row.price_bs.to_d.to_f,
          }
        end,
        print_material_options: service.service_print_material_surcharges
          .sort_by { |row| [row.created_at || Time.at(0), row.id.to_i] }
          .map do |row|
          required_quantity = row.respond_to?(:required_quantity) ? row.required_quantity.to_d : 1.to_d
          {
            id: row.id,
            product_id: row.producto_id,
            label: row.display_label.to_s,
            product_name: row.producto&.descripcion.to_s,
            required_quantity: required_quantity.to_f,
            surcharge_percent: row.surcharge_percent.to_d.to_f,
            include_product_price_in_sale: row.include_product_price_in_sale?,
            product_price_usd: row.producto&.precio_venta_usd.to_d.to_f,
          }
        end,
        print_volume_discounts: service.service_print_volume_discounts
          .sort_by { |row| [row.min_quantity.to_i, row.discount_percent.to_d, row.id.to_i] }
          .map do |row|
          {
            min_quantity: row.min_quantity.to_i,
            discount_percent: row.discount_percent.to_d.to_f,
          }
        end,
        consumable_costs: consumable_costs,
        scheduled_discount_rules: serialize_discount_rules_for_front(
          service_discount_rules[service.id],
          default_fixed_currency: service_discount_currency(service),
          default_fixed_symbol: (service_discount_currency(service) == 'VES' ? 'Bs' : '$')
        ),
      }
    end
  end

  def ventas_products_scope
    current_business
      .productos
      .with_attached_foto
      .includes(:categoria, :product_variations, :stock_lot_variations, :stock_lots)
      .order(:descripcion)
  end

  def ventas_services_scope
    current_business
      .services
      .includes(
        :system_service,
        :print_delivery_material_surcharge,
        :service_print_coverage_prices,
        :service_print_volume_discounts,
        { service_print_material_surcharges: :producto },
        service_expense_structures: [
          :service_manager_expenses,
          :service_variable_expenses,
          { service_product_expenses: [:product_variation, { producto: :product_variations }] },
        ],
      )
      .where(available: true)
      .visible_for_user(Current.user)
      .order("system_services.name ASC, services.description ASC")
  end

  def paginate_scope(scope, page:, items:)
    offset = [page - 1, 0].max * items
    scope.offset(offset).limit(items)
  end

  def next_page_for(total_count:, page:, items:)
    page * items < total_count ? page + 1 : nil
  end

  def current_bcv_rate_for_sales
    @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : 0.to_d
  end

  def open_shift_balance_checks_payload
    cash_bs = current_business.accounts.find_by(account_type: "cash_box", currency: "VES", cash_role: "cash_box")
    cash_usd = current_business.accounts.find_by(account_type: "cash_box", currency: "USD", cash_role: "cash_box")
    payall = current_business.accounts
                             .where("LOWER(name) LIKE ?", "%payall%")
                             .order(active: :desc, id: :asc)
                             .first

    [
      {
        label: "Caja Efectivo Bs",
        balance: cash_bs&.balance.to_d.to_f,
        currency_symbol: cash_bs&.currency_symbol.presence || "Bs",
      },
      {
        label: "Caja Efectivo $",
        balance: cash_usd&.balance.to_d.to_f,
        currency_symbol: cash_usd&.currency_symbol.presence || "$",
      },
      {
        label: "Payall",
        balance: payall&.balance.to_d.to_f,
        currency_symbol: payall&.currency_symbol.presence || "$",
      },
    ]
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
      created_by_name: venta.user&.display_name,
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
      phone: cliente.phone.to_s,
      has_benefits: cliente.has_special_benefits?,
      benefits: cliente.normalized_benefits_config,
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

    reservations = []

    grouped_items.each do |(producto_id, variation_id), grouped_rows|
      quantity_units = grouped_rows.sum { |row| row.quantity.to_d }
      next unless quantity_units.positive?

      producto = current_business.productos.find_by(id: producto_id)
      next unless producto

      lot_breakdown = producto.consume_variation_stock_with_breakdown!(variation_id: variation_id,
                                                                       quantity_units: quantity_units)

      lot_breakdown.each do |entry|
        reservations << {
          "product_id" => producto_id,
          "variation_id" => variation_id,
          "stock_lot_id" => entry[:stock_lot_id],
          "quantity" => entry[:quantity].to_d.to_f,
          "unit_cost_usd" => entry[:unit_cost_usd].to_d.to_f,
        }
      end
    end

    reservations
  end

  def reserve_service_product_expenses_for_items!(service_item_rows, venta:)
    grouped = Hash.new(0.to_d)

    service_item_rows.each do |entry|
      service = entry[:service]
      quantity_multiplier = entry[:quantity].to_d
      next unless service && quantity_multiplier.positive?

      collect_print_material_consumption!(
        service: service,
        payload: entry[:payload],
        multiplier: quantity_multiplier,
        grouped: grouped,
      )

      next unless service_cost_debit_enabled?(service)

      # Los productos de consumo en estructura de costos se desactivaron;
      # el descuento de stock se controla por la presentacion fisica del servicio.
    end

    reservations = []
    grouped.each do |(producto_id, variation_id), quantity_units|
      next unless quantity_units.positive?

      producto = current_business.productos.find_by(id: producto_id)
      next unless producto

      lot_breakdown = producto.consume_variation_stock_with_breakdown!(
        variation_id: variation_id,
        quantity_units: quantity_units
      )

      lot_breakdown.each do |entry|
        reservations << {
          "product_id" => producto_id,
          "variation_id" => variation_id,
          "stock_lot_id" => entry[:stock_lot_id],
          "quantity" => entry[:quantity].to_d.to_f,
          "unit_cost_usd" => entry[:unit_cost_usd].to_d.to_f,
        }
      end
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
      }
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
    end
  end

  def collect_print_material_consumption!(service:, payload:, multiplier:, grouped:)
    return if service.blank?

    source = payload.respond_to?(:to_h) ? payload.to_h : {}
    delivery_presentation = (source["delivery_presentation"] || source[:delivery_presentation]).to_s.strip.downcase

    if service.printing_type_service?
      # Para servicios de impresion, cada fila representa impresion fisica y siempre consume material.
    elsif service.lamination_type_service?
      # Para servicios de plastificacion vendidos directamente, el material se selecciona en el POS.
    else
      return unless delivery_presentation == "physical"
    end

    return unless multiplier.to_d.positive?

    material_rows = source["selected_print_material_rows"] || source[:selected_print_material_rows]
    consumed_from_rows = false

    if material_rows.is_a?(Array)
      material_rows.each do |raw_row|
        row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
        row_product_id = row["product_id"] || row[:product_id]
        row_variation_id = row["variation_id"] || row[:variation_id]
        row_quantity = parse_decimal(row["quantity"] || row[:quantity], default: 0)
        next unless row_product_id.present? && row_quantity.positive?

        product = current_business.productos.includes(:product_variations).find_by(id: row_product_id)
        next if product.blank? || product.business_id != current_business.id

        variation = (product.product_variations.find_by(id: row_variation_id) if row_variation_id.present?)
        variation ||= product.product_variations.to_a.min_by(&:id)
        next unless variation

        grouped[[product.id, variation.id]] += (multiplier.to_d * row_quantity.to_d)
        consumed_from_rows = true
      end

      return if consumed_from_rows
    end

    if service.lamination_type_service?
      service.service_print_material_surcharges.includes(:producto).find_each do |surcharge|
        product = surcharge.producto
        next if product.blank? || product.business_id != current_business.id

        variation = product.product_variations.to_a.min_by(&:id)
        next unless variation

        required_quantity = surcharge.respond_to?(:required_quantity) ? surcharge.required_quantity.to_d : 1.to_d
        grouped[[product.id, variation.id]] += (multiplier.to_d * required_quantity)
      end

      return
    end

    material_product_id = source["selected_print_material_product_id"] || source[:selected_print_material_product_id]
    product = nil

    if material_product_id.present?
      product = current_business.productos.includes(:product_variations).find_by(id: material_product_id)
    end

    if product.nil?
      surcharge_id = source["selected_print_material_surcharge_id"] || source[:selected_print_material_surcharge_id]
      return if surcharge_id.blank?

      surcharge = service.service_print_material_surcharges.find_by(id: surcharge_id)
      return unless surcharge&.producto

      product = surcharge.producto
    end

    return if product.business_id != current_business.id

    variation = product.product_variations.to_a.min_by(&:id)
    return unless variation

    grouped[[product.id, variation.id]] += multiplier.to_d
  end

  def restore_reserved_service_stock_from_notes!(venta, strict: true)
    notes_payload = parse_notes_payload(venta.notes)
    rows = Array(notes_payload["reserved_service_products"])
    rows.each do |row|
      producto_id = row["product_id"] || row[:product_id]
      variation_id = row["variation_id"] || row[:variation_id]
      stock_lot_id = row["stock_lot_id"] || row[:stock_lot_id]
      quantity_units = parse_decimal(row["quantity"] || row[:quantity], default: 0)
      next if producto_id.blank? || variation_id.blank? || !quantity_units.positive?

      if stock_lot_id.present?
        restored_exact = restore_product_variation_units_in_lot!(
          producto_id: producto_id,
          variation_id: variation_id,
          stock_lot_id: stock_lot_id,
          quantity_units: quantity_units,
          venta: venta,
          strict: strict,
        )
        next if restored_exact
      end

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
    end
  end

  def restore_product_variation_units_in_lot!(producto_id:, variation_id:, stock_lot_id:, quantity_units:, venta:, strict: true)
    producto = current_business.productos.find_by(id: producto_id)
    if producto.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro el producto ##{producto_id} para restaurar stock de la venta ##{venta.id}."
    end

    lot = producto.stock_lots.find_by(id: stock_lot_id)
    if lot.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro el lote ##{stock_lot_id} para restaurar stock de la venta ##{venta.id}."
    end

    row = lot.variation_row_for(variation_id, create_if_missing: true)
    if row.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro la variacion para restaurar en el lote ##{lot.id} de la venta ##{venta.id}."
    end

    current_remaining = row.quantity_remaining.to_d
    max_quantity = row.quantity_in.to_d
    available_capacity = max_quantity - current_remaining

    if quantity_units.to_d > available_capacity
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se pudo restaurar en el lote ##{lot.id} toda la cantidad de la venta ##{venta.id}."
    end

    row.update!(quantity_remaining: current_remaining + quantity_units.to_d)
    lot.sync_quantity_remaining_from_variations!
    true
  end

  def normalized_client_benefits_config(cliente)
    return {} unless cliente

    cliente.normalized_benefits_config
  rescue StandardError
    {}
  end

  def client_product_unit_price_usd(product:, benefits_config: {})
    base_price = product.precio_venta_usd.to_d
    return base_price unless benefits_config.is_a?(Hash)

    config = benefits_config.deep_stringify_keys
    product_rules = config["product_rules"]
    specific_rule = product_rules.is_a?(Hash) ? product_rules[product.id.to_s] : nil

    if specific_rule.is_a?(Hash)
      mode = specific_rule["mode"].to_s
      value = specific_rule["value"].to_d
      if mode == "fixed" && value.positive?
        return value.round(2)
      end

      if mode == "percent" && value.positive?
        percent = [value, 100.to_d].min
        discounted = base_price * (1 - (percent / 100))
        return discounted.positive? ? discounted.round(2) : 0.to_d
      end
    end

    general_percent = config["general_product_discount_percent"].to_d
    return base_price unless general_percent.positive?

    general_percent = [general_percent, 100.to_d].min
    discounted = base_price * (1 - (general_percent / 100))
    discounted.positive? ? discounted.round(2) : 0.to_d
  end

  def client_service_fixed_price_usd(benefits_config:, service_id:)
    return 0.to_d unless benefits_config.is_a?(Hash)

    service_prices = benefits_config.deep_stringify_keys["service_fixed_prices"]
    return 0.to_d unless service_prices.is_a?(Hash)

    amount = service_prices[service_id.to_s].to_d
    return 0.to_d unless amount.positive?

    amount.round(2)
  end

  def active_discount_rules
    @active_discount_rules ||= current_business
      .discount_schedules
      .enabled
      .active_on(Date.current)
      .to_a
  end

  def active_discount_rules_by_target(target)
    target_key = target.to_s
    @active_discount_rules_by_target ||= {}
    return @active_discount_rules_by_target[target_key] if @active_discount_rules_by_target.key?(target_key)

    filtered = active_discount_rules.select { |rule| rule.applies_to.to_s == target_key }

    @active_discount_rules_by_target[target_key] = filtered.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |rule, hash|
      target_ids = target_key == 'products' ? rule.product_ids : rule.service_ids
      Array(target_ids).each do |target_id|
        hash[target_id.to_i] << rule
      end
    end
  end

  def apply_discount_schedule_to_unit_price_usd(base_unit_price_usd:, quantity:, rules:, fixed_currency:, tasa_dolar:)
    unit_price_usd = base_unit_price_usd.to_d
    return unit_price_usd unless unit_price_usd.positive?

    applicable_rule = pick_discount_rule_for_quantity(rules, quantity)
    return unit_price_usd if applicable_rule.blank?

    if applicable_rule.discount_mode.to_s == 'percent'
      percent = [applicable_rule.discount_value.to_d, 100.to_d].min
      discounted = unit_price_usd * (1 - (percent / 100))
      return discounted.positive? ? discounted.round(6) : 0.to_d
    end

    fixed_amount = applicable_rule.discount_value.to_d
    fixed_amount_usd = if fixed_currency.to_s == 'VES'
        tasa = tasa_dolar.to_d
        tasa.positive? ? (fixed_amount / tasa) : 0.to_d
      else
        fixed_amount
      end

    fixed_amount_usd.positive? ? fixed_amount_usd.round(6) : 0.to_d
  end

  def apply_discount_schedule_to_unit_price_amount(base_unit_price_amount:, quantity:, rules:, fixed_currency:,
                                                   target_currency:, tasa_dolar:)
    unit_price_amount = base_unit_price_amount.to_d
    return unit_price_amount.round(2) unless unit_price_amount.positive?

    applicable_rule = pick_discount_rule_for_quantity(rules, quantity)
    return unit_price_amount.round(2) if applicable_rule.blank?

    if applicable_rule.discount_mode.to_s == 'percent'
      percent = [applicable_rule.discount_value.to_d, 100.to_d].min
      discounted = unit_price_amount * (1 - (percent / 100))
      return discounted.positive? ? discounted.round(2) : 0.to_d
    end

    fixed_amount = applicable_rule.discount_value.to_d
    converted_amount = convert_discount_amount_to_currency(
      amount: fixed_amount,
      from_currency: fixed_currency,
      to_currency: target_currency,
      tasa_dolar: tasa_dolar,
    )

    converted_amount.to_d.positive? ? converted_amount.to_d.round(2) : 0.to_d
  end

  def pick_discount_rule_for_quantity(rules, quantity)
    qty = quantity.to_d
    return nil unless qty.positive?

    Array(rules)
      .select { |rule| discount_rule_applies_to_quantity?(rule, qty) }
      .max_by { |rule| [rule.quantity_threshold.to_i, rule.id.to_i] }
  end

  def discount_rule_applies_to_quantity?(rule, quantity)
    threshold = rule.quantity_threshold.to_d
    return false unless threshold.positive?

    if rule.quantity_mode.to_s == 'exact_quantity'
      quantity == threshold
    else
      quantity >= threshold
    end
  end

  def service_discount_currency(service)
    return 'USD' if service.blank?

    reference = service.currency_base_price.to_s.strip
    %W[#{Service::BOLIVAR_REFERENCE} Unidad\ VI].include?(reference) ? 'VES' : 'USD'
  end

  def service_uses_ves_reference_pricing?(service)
    return false if service.blank?

    reference = service.currency_base_price.to_s.strip
    %W[#{Service::BOLIVAR_REFERENCE} Unidad\ VI].include?(reference)
  end

  def convert_discount_amount_to_currency(amount:, from_currency:, to_currency:, tasa_dolar:)
    return amount.to_d if from_currency.to_s == to_currency.to_s

    convert_payment_to_currency(amount, from_currency, to_currency, tasa_dolar)
  end

  def serialize_discount_rules_for_front(rules, default_fixed_currency:, default_fixed_symbol:)
    Array(rules).map do |rule|
      {
        id: rule.id,
        quantity_mode: rule.quantity_mode.to_s,
        quantity_threshold: rule.quantity_threshold.to_i,
        discount_mode: rule.discount_mode.to_s,
        discount_value: rule.discount_value.to_d.to_f,
        fixed_currency: default_fixed_currency,
        fixed_symbol: default_fixed_symbol,
      }
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
        :recarga_base_amount,
        :recarga_total_amount,
        :recarga_profit_percent,
        :agreed_price_display,
        :agreed_reference_name,
        :agreed_reference_amount,
        :agreed_reference_symbol,
        :delivery_presentation,
        :service_beneficiary_name,
        :service_responsible_name,
        :selected_print_coverage_id,
        :selected_print_coverage_percent,
        :selected_print_price_bs,
        :selected_print_surcharge_percent,
        :selected_print_unit_price_bs,
        :printing_discount_percent,
        :selected_print_material_surcharge_id,
        :selected_print_material_product_id,
        :selected_print_material_label,
        { selected_print_material_rows: %i[surcharge_id product_id label quantity breakdown_in_invoice
                                          optional_delivery_extra requested_quantity variation_id] },
        :price_signature,
        { consumable_decisions: %i[service_product_expense_id delivered product_variation_id] },
      ],
      payments: %i[method amount account_id currency reference payment_date],
      change: %i[method amount account_id currency reference],
      credit_sale: %i[enabled due_on],
      cashea: [
        :enabled,
        :account_id,
        :initial_usd,
        :min_purchase_usd,
        { installments: %i[amount_usd due_on] },
      ],
      checkout_discount: %i[enabled amount reason],
      totals: %i[taxable_subtotal_base exento_subtotal_base vat_base total_base],
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

  def service_item_discounts_payload_for_sale(venta:, service_item_rows:)
    return {} if venta.blank? || service_item_rows.blank?

    service_items = venta.venta_items.select { |item| item.producto_id.blank? }
    return {} if service_items.empty?

    discounts = {}
    index = 0

    service_item_rows.each do |entry|
      item = service_items[index]
      index += 1
      next unless item

      discount_percent = parse_decimal(entry[:printing_discount_percent], default: 0)
      next unless discount_percent.positive?

      discounts[item.id] = discount_percent.to_d.to_f
    end

    discounts
  end

  def service_cost_settlements_payload_for_notes(settlements)
    Array(settlements).map do |row|
      service = row[:service]

      {
        "service_id" => service&.id,
        "service_name" => service&.description.to_s,
        "service_beneficiary_name" => normalize_service_party_name(row[:service_beneficiary_name]),
        "service_responsible_name" => normalize_service_party_name(row[:service_responsible_name]),
        "delivery_presentation" => row[:delivery_presentation].to_s.presence,
        "quantity" => row[:quantity].to_d.to_f,
        "unit_cost_usd" => row[:unit_cost_usd].to_d.to_f,
        "total_cost_usd" => row[:total_cost_usd].to_d.to_f,
        "paid_cost_usd" => row[:paid_cost_usd].to_d.to_f,
        "pending_cost_usd" => row[:pending_cost_usd].to_d.to_f,
        "detail_lines" => normalize_service_cost_lines_payload(row[:detail_lines]),
      }
    end
  end

  def sold_service_printings_payload_for_notes(service_item_rows:, tasa_dolar:)
    rows = []
    unidad_vi = parse_decimal(@unidad_VI, default: TasaCambio.latest_value("Unidad VI"))

    Array(service_item_rows).each do |entry|
      service = entry[:service]
      quantity = entry[:quantity].to_d
      payload_hash = entry[:payload].respond_to?(:to_h) ? entry[:payload].to_h : {}

      next if service.blank? || quantity <= 0

      delivery_presentation = normalize_service_delivery_presentation(
        payload_hash["delivery_presentation"] || payload_hash[:delivery_presentation],
        service: service,
      )
      next unless delivery_presentation == "physical"
      next unless service.delivery_physical_enabled?
      next if service.printing_type_service?

      printing_payload = build_service_physical_printing_payload(service: service, tasa_dolar: tasa_dolar)
      next unless printing_payload[:enabled]

      printing_service_id = Array(printing_payload[:pages])
        .filter_map do |row|
        row[:print_type_service_id].to_i if row[:print_type_service_id].to_i.positive?
      end
        .first
      if printing_service_id.to_i.positive?
        printing_service = current_business.services.find_by(id: printing_service_id)
      end
      material_labels = Array(printing_payload[:pages])
        .filter_map { |row| row[:material_label].to_s.strip.presence }
        .uniq
      child_service_label = printing_service&.print_sale_display_name.to_s.strip.presence || "Impresion"
      child_service_label = append_selected_material_to_service_name(
        child_service_label,
        material_labels.join(" / ")
      )

      unit_sale_price_bs = printing_payload[:cost_bs].to_d.round(2)
      next unless unit_sale_price_bs.positive?

      unit_sale_price_usd = printing_payload[:cost_usd].to_d.round(2)
      next unless unit_sale_price_usd.positive?

      total_sale_price_bs = (unit_sale_price_bs * quantity).round(2)
      next unless total_sale_price_bs.positive?

      total_sale_price_usd = (unit_sale_price_usd * quantity).round(2)
      next unless total_sale_price_usd.positive?

      parent_service_name = service_sale_display_name(service: service, payload: payload_hash)

      rows << {
        "classification" => "printing_service",
        "classification_label" => "Servicio de impresion",
        "service_id" => service.id,
        "printing_service_id" => (printing_service_id if printing_service_id.to_i.positive?),
        "parent_service_name" => parent_service_name,
        "source_name" => child_service_label,
        "quantity" => quantity.to_f,
        "unit_sale_price_bs" => unit_sale_price_bs.to_f,
        "total_sale_price_bs" => total_sale_price_bs.to_f,
        "unit_sale_price_usd" => unit_sale_price_usd.to_f,
        "total_sale_price_usd" => total_sale_price_usd.to_f,
      }

      Array(printing_payload[:lamination_rows]).each do |lamination_row|
        lamination_service_id = lamination_row[:service_id].to_i
        next unless lamination_service_id.positive?

        lamination_service = current_business.services.find_by(id: lamination_service_id)
        next if lamination_service.blank?

        child_quantity = (lamination_row[:quantity].to_d * quantity).round(2)
        next unless child_quantity.positive?

        child_unit_price_bs = lamination_service.unit_price_bs(tasa_dolar: tasa_dolar,
                                                               unidad_vi: unidad_vi).to_d.round(2)
        child_unit_price_usd = lamination_service.unit_price_usd(tasa_dolar: tasa_dolar,
                                                                 unidad_vi: unidad_vi).to_d.round(2)

        if !child_unit_price_bs.positive? && child_unit_price_usd.positive? && tasa_dolar.to_d.positive?
          child_unit_price_bs = (child_unit_price_usd * tasa_dolar.to_d).round(2)
        end
        if !child_unit_price_usd.positive? && child_unit_price_bs.positive? && tasa_dolar.to_d.positive?
          child_unit_price_usd = (child_unit_price_bs / tasa_dolar.to_d).round(2)
        end

        next unless child_unit_price_bs.positive? || child_unit_price_usd.positive?

        child_total_price_bs = (child_unit_price_bs * child_quantity).round(2)
        child_total_price_usd = (child_unit_price_usd * child_quantity).round(2)

        child_source_name = lamination_service.print_sale_display_name.to_s.strip.presence || "Plastificacion"

        rows << {
          "classification" => "lamination_service",
          "classification_label" => "Servicio de plastificacion",
          "service_id" => service.id,
          "printing_service_id" => lamination_service.id,
          "parent_service_name" => parent_service_name,
          "source_name" => child_source_name,
          "quantity" => child_quantity.to_f,
          "unit_sale_price_bs" => child_unit_price_bs.to_f,
          "total_sale_price_bs" => child_total_price_bs.to_f,
          "unit_sale_price_usd" => child_unit_price_usd.to_f,
          "total_sale_price_usd" => child_total_price_usd.to_f,
        }
      end

      additional_delivery_rows = Array(payload_hash["selected_print_material_rows"] || payload_hash[:selected_print_material_rows]).filter_map do |raw_row|
        row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
        optional_delivery_extra = ActiveModel::Type::Boolean.new.cast(row["optional_delivery_extra"] || row[:optional_delivery_extra])
        breakdown_in_invoice = ActiveModel::Type::Boolean.new.cast(row["breakdown_in_invoice"] || row[:breakdown_in_invoice])
        next unless optional_delivery_extra && breakdown_in_invoice

        product_id = row["product_id"] || row[:product_id]
        variation_id = row["variation_id"] || row[:variation_id]
        per_service_quantity = parse_decimal(row["quantity"] || row[:quantity], default: 0)
        next if product_id.blank? || per_service_quantity <= 0

        product = current_business.productos.find_by(id: product_id)
        next if product.blank?

        total_quantity = (per_service_quantity.to_d * quantity).round(2)
        next unless total_quantity.positive?

        source_label = row["label"] || row[:label]
        source_label = source_label.to_s.strip.presence || product.descripcion.to_s

        unit_sale_price_usd = product.precio_venta_usd.to_d.round(2)
        unit_sale_price_bs = if tasa_dolar.to_d.positive?
            (unit_sale_price_usd * tasa_dolar.to_d).round(2)
          else
            0.to_d
          end
        total_sale_price_usd = (unit_sale_price_usd * total_quantity).round(2)
        total_sale_price_bs = (unit_sale_price_bs * total_quantity).round(2)

        {
          "classification" => "physical_delivery_extra_product",
          "classification_label" => "Producto adicional de entrega",
          "service_id" => service.id,
          "parent_service_name" => parent_service_name,
          "source_name" => source_label,
          "product_id" => product.id,
          "variation_id" => variation_id.to_i.positive? ? variation_id.to_i : nil,
          "quantity" => total_quantity.to_f,
          "unit_sale_price_bs" => unit_sale_price_bs.to_f,
          "total_sale_price_bs" => total_sale_price_bs.to_f,
          "unit_sale_price_usd" => unit_sale_price_usd.to_f,
          "total_sale_price_usd" => total_sale_price_usd.to_f,
          "invoice_breakdown_only" => true,
        }
      end

      rows.concat(additional_delivery_rows)
    end

    rows
  end

  def sold_service_parties_payload_for_notes(service_item_rows)
    Array(service_item_rows).filter_map do |entry|
      service = entry[:service]
      next unless service

      payload_hash = entry[:payload].respond_to?(:to_h) ? entry[:payload].to_h : {}
      beneficiary_name = normalize_service_party_name(
        payload_hash["service_beneficiary_name"] || payload_hash[:service_beneficiary_name]
      )
      responsible_name = normalize_service_party_name(
        payload_hash["service_responsible_name"] || payload_hash[:service_responsible_name]
      )
      next if beneficiary_name.blank? && responsible_name.blank?

      {
        "service_id" => service.id,
        "service_name" => service.description.to_s,
        "sale_display_name" => service_sale_display_name(service: service, payload: payload_hash).to_s,
        "service_beneficiary_name" => beneficiary_name,
        "service_responsible_name" => responsible_name,
      }
    end
  end

  def build_service_cost_obligations(service_item_rows:, tasa_dolar:)
    grouped_rows = Hash.new do |hash, key|
      hash[key] = {
        service: nil,
        quantity: 0.to_d,
        delivery_presentation: nil,
        service_beneficiary_name: nil,
        service_responsible_name: nil,
        consumable_decisions: {},
      }
    end

    service_item_rows.each do |entry|
      service = entry[:service]
      quantity = entry[:quantity].to_d
      next unless service
      next unless service.id.present?
      next unless quantity.positive?
      next unless service_cost_debit_enabled?(service)

      payload_hash = entry[:payload].respond_to?(:to_h) ? entry[:payload].to_h : {}
      delivery_presentation = normalize_service_delivery_presentation(
        payload_hash["delivery_presentation"] || payload_hash[:delivery_presentation],
        service: service,
      )

      group_key = [service.id, delivery_presentation.presence || "none"].join(":")

      grouped_rows[group_key][:service] = service
      grouped_rows[group_key][:quantity] += quantity
      grouped_rows[group_key][:delivery_presentation] = delivery_presentation
      beneficiary_name = normalize_service_party_name(
        payload_hash["service_beneficiary_name"] || payload_hash[:service_beneficiary_name]
      )
      responsible_name = normalize_service_party_name(
        payload_hash["service_responsible_name"] || payload_hash[:service_responsible_name]
      )
      grouped_rows[group_key][:service_beneficiary_name] ||= beneficiary_name if beneficiary_name.present?
      grouped_rows[group_key][:service_responsible_name] ||= responsible_name if responsible_name.present?

      normalize_service_product_decisions(entry[:payload]).each do |expense_id, decision_row|
        grouped_rows[group_key][:consumable_decisions][expense_id.to_s] = decision_row
      end
    end

    unidad_vi = parse_decimal(@unidad_VI, default: TasaCambio.latest_value("Unidad VI"))
    obligations = []

    grouped_rows.each_value do |row|
      service = row[:service]
      quantity = row[:quantity].to_d
      next unless service
      next unless quantity.positive?

      detail_lines = build_service_cost_detail_lines(
        service: service,
        multiplier: quantity,
        tasa_dolar: tasa_dolar,
        unidad_vi: unidad_vi,
        delivery_presentation: row[:delivery_presentation],
        consumable_decisions: row[:consumable_decisions],
      )

      total_cost_usd = detail_lines.sum { |line| line["amount_usd"].to_d }.round(2)
      next unless total_cost_usd.positive?

      unit_cost_usd = (total_cost_usd / quantity).round(2)

      obligations << {
        service: service,
        service_id: service.id,
        quantity: quantity,
        delivery_presentation: row[:delivery_presentation],
        service_beneficiary_name: row[:service_beneficiary_name],
        service_responsible_name: row[:service_responsible_name],
        unit_cost_usd: unit_cost_usd,
        total_cost_usd: total_cost_usd,
        detail_lines: detail_lines,
      }
    end

    [obligations, nil]
  end

  def build_service_cost_detail_lines(service:, multiplier:, tasa_dolar:, unidad_vi:, delivery_presentation: nil,
                                      consumable_decisions: {})
    return [] unless service

    line_sequence = 0
    lines = []

    service.service_expense_structures.where(active_for_sales: true).includes(
      { service_manager_expenses: :manager },
      :service_variable_expenses,
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
          "breakdown_in_invoice" => expense.breakdown_in_invoice?,
        }
      end

      next unless delivery_presentation.to_s == "physical" && service.delivery_physical_enabled?

      pages = normalize_print_delivery_pages_for_sale(service)
      next unless pages.present?

      type_service_ids = pages.map { |page_row| page_row["print_type_service_id"].to_i }.uniq
      type_services_by_id = current_business
        .services
        .includes(:service_print_coverage_prices)
        .where(id: type_service_ids)
        .index_by(&:id)

      unit_printing_bs = pages.sum do |page_row|
        type_service = type_services_by_id[page_row["print_type_service_id"].to_i]
        next 0.to_d if type_service.blank?

        prices = type_service.service_print_coverage_prices.ordered_by_coverage.to_a
        next 0.to_d if prices.empty?

        resolve_printing_price_bs_for_coverage(
          coverage_percent: page_row["coverage_percent"].to_d,
          prices: prices,
        )
      end

      next unless unit_printing_bs.to_d.positive?

      total_printing_bs = (unit_printing_bs.to_d * multiplier.to_d).round(2)
      next unless total_printing_bs.positive? && tasa_dolar.to_d.positive?

      total_printing_usd = (total_printing_bs / tasa_dolar.to_d).round(2)

      line_sequence += 1
      lines << {
        "line_id" => "service-#{service.id}-line-#{line_sequence}",
        "service_id" => service.id,
        "service_name" => service.description.to_s,
        "structure_id" => structure.id,
        "structure_description" => structure_label,
        "classification" => "printing_expense",
        "classification_label" => "Impresion fisica",
        "source_type" => "PrintCoverageService",
        "source_id" => type_service_ids.first,
        "source_name" => "Impresion fisica (#{pages.size} pagina(s))",
        "quantity" => multiplier.to_d.to_f,
        "amount_usd" => total_printing_usd.to_f,
        "paid_usd" => 0.0,
        "pending_usd" => total_printing_usd.to_f,
        "status" => "pending",
        "source_updatable" => false,
        "source_currency_reference" => "Bs",
        "source_amount_reference_unit" => unit_printing_bs.to_d.round(2).to_f,
        "source_amount_reference_total" => total_printing_bs.to_f,
      }
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

  def service_sale_display_name(service:, payload:)
    base_name = service&.print_sale_display_name.to_s.strip
    base_name = service&.description.to_s.strip if base_name.blank?
    base_name = "Servicio" if base_name.blank?

    payload_hash = payload.respond_to?(:to_h) ? payload.to_h : {}
    if service&.printing_type_service?
      material_label = payload_hash[:selected_print_material_label] || payload_hash["selected_print_material_label"]
      if material_label.blank?
        material_label = Array(payload_hash[:selected_print_material_rows] || payload_hash["selected_print_material_rows"])
          .filter_map do |row|
          raw = row.respond_to?(:to_h) ? row.to_h : {}
          raw["label"] || raw[:label]
        end
          .map do |label|
          label.to_s.strip
        end
          .reject(&:blank?)
          .uniq
          .first
      end

      base_name = append_selected_material_to_service_name(base_name, material_label)
    end

    return base_name unless recarga_service?(service)

    recarga_amount = parse_decimal(payload_hash[:recarga_base_amount] || payload_hash["recarga_base_amount"],
                                   default: 0)
    return base_name unless recarga_amount.positive?

    amount_label = format_recarga_bs_amount(recarga_amount)
    "Recarga #{base_name} #{amount_label}"
  end

  def append_selected_material_to_service_name(base_name, material_label)
    safe_base = base_name.to_s.strip.presence || "Servicio"
    safe_material = material_label.to_s.strip
    return safe_base if safe_material.blank?

    "#{safe_base} #{safe_material}".squish
  end

  def recarga_service?(service)
    service&.system_service&.recarga_system?
  end

  def format_recarga_bs_amount(amount)
    formatted = ApplicationController.helpers.format_quantity(amount.to_d.round(2), precision: 2)
    "#{formatted} Bs"
  end

  def recarga_config_for(service)
    return nil unless service&.system_service&.recarga_system?

    {
      min_amount: service.recarga_min_amount.to_d,
      multiple_amount: service.recarga_multiple_amount.to_d,
      profit_percent: service.recarga_profit_percent.to_d,
    }
  end

  def resolve_recarga_pricing(service:, payload:, tasa_dolar:, base_currency:)
    config = recarga_config_for(service)
    return nil unless config

    payload_hash = payload.respond_to?(:to_h) ? payload.to_h : {}
    base_amount = parse_decimal(payload_hash[:recarga_base_amount] || payload_hash["recarga_base_amount"], default: 0)

    return { error: "Debes indicar el monto de la recarga." } unless base_amount.positive?
    if config[:min_amount].positive? && base_amount < config[:min_amount]
      return { error: "El monto minimo de recarga es #{format_recarga_bs_amount(config[:min_amount])}." }
    end

    if config[:multiple_amount].positive?
      remainder = (base_amount % config[:multiple_amount]).to_d
      if remainder > 0.01
        return { error: "El monto debe ser multiplo de #{format_recarga_bs_amount(config[:multiple_amount])}." }
      end
    end

    total_amount = (base_amount * (1 + config[:profit_percent] / 100)).round(2)
    return { error: "No hay tasa BCV disponible para calcular la recarga." } unless tasa_dolar.to_d.positive?

    unit_price_usd = (total_amount / tasa_dolar.to_d).round(6)
    unit_price_base_amount = if base_currency == "VES"
        total_amount
      else
        (total_amount / tasa_dolar.to_d).round(2)
      end

    {
      base_amount: base_amount,
      total_amount: total_amount,
      profit_percent: config[:profit_percent],
      unit_price_usd: unit_price_usd,
      unit_price_base_amount: unit_price_base_amount,
      unit_price_base_currency: base_currency,
    }
  end

  def payall_account
    current_business.accounts.find do |account|
      account.name.to_s.strip.downcase.include?("payall")
    end
  end

  def recarga_debit_entries(service_item_rows)
    Array(service_item_rows).filter_map do |entry|
      pricing = entry[:recarga_pricing]
      next if pricing.blank?

      quantity = entry[:quantity].to_d
      next unless quantity.positive?

      base_amount = pricing[:base_amount].to_d
      next unless base_amount.positive?

      {
        service: entry[:service],
        amount: (base_amount * quantity).round(2),
      }
    end
  end

  def payall_draft_movements_scope(draft)
    return AccountMovement.none if draft.blank?

    AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where("account_movements.description LIKE ?", "%[VENTA_DRAFT:#{draft.id}]%")
  end

  def payall_draft_reserved_total(draft)
    payall_draft_movements_scope(draft).sum(:amount).to_d
  end

  def delete_payall_draft_movements!(draft)
    payall_draft_movements_scope(draft).find_each(&:destroy!)
  end

  def relabel_payall_draft_movements!(draft, venta)
    return if draft.blank? || venta.blank?

    payall_draft_movements_scope(draft).find_each do |movement|
      base = movement.description.to_s.gsub(/\s*\[VENTA_DRAFT:\d+\]/i, "").strip
      movement.update!(description: "#{base} [VENTA:#{venta.id}]")
    end
  end

  def sync_payall_recarga_movements_for_draft!(draft, entries)
    delete_payall_draft_movements!(draft)

    account = payall_account
    return if account.blank?

    entries.each do |entry|
      amount = entry[:amount].to_d
      next unless amount.positive?

      service_name = entry[:service]&.description.to_s.strip.presence || "Recarga"
      account.account_movements.create!(
        movement_kind: "expense",
        amount: amount,
        description: "Recarga Payall #{service_name} [VENTA_DRAFT:#{draft.id}]",
        occurred_at: Time.current,
      )
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
            return [nil, "La referencia del pago de costo para #{service_label} debe tener 4 digitos."]
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

      movement_attrs[:reference] = payment_row[:reference].presence if payment_row[:reference].present?

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
      "service_beneficiary_name" => normalize_service_party_name(settlement[:service_beneficiary_name]),
      "service_responsible_name" => normalize_service_party_name(settlement[:service_responsible_name]),
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

  def apply_printing_discount_pricing(service:, payload:, unit_price_usd:, unit_price_base_amount:, tasa_dolar:,
                                      base_currency:)
    return [unit_price_usd, unit_price_base_amount, nil] unless service&.printing_type_service?

    discount_percent = parse_decimal(payload[:printing_discount_percent] || payload["printing_discount_percent"],
                                     default: 0).to_d
    return [unit_price_usd, unit_price_base_amount, nil] unless discount_percent.positive?

    discount_percent = [discount_percent, 100.to_d].min

    base_unit_bs = parse_decimal(payload[:selected_print_unit_price_bs] || payload["selected_print_unit_price_bs"],
                                 default: 0).to_d
    unless base_unit_bs.positive? && tasa_dolar.to_d.positive?
      return [unit_price_usd, unit_price_base_amount,
              discount_percent]
    end

    discounted_bs = (base_unit_bs * (1 - (discount_percent / 100))).round(2)
    adjusted_unit_price_usd = (discounted_bs / tasa_dolar.to_d).round(6)
    adjusted_base_amount = base_currency == "VES" ? discounted_bs : (discounted_bs / tasa_dolar.to_d).round(2)

    [adjusted_unit_price_usd, adjusted_base_amount, discount_percent]
  end

  def sale_item_discounts_payload(venta)
    notes_payload = parse_notes_payload(venta&.notes)
    raw = notes_payload["service_item_discounts"]
    return {} unless raw.is_a?(Hash)

    raw.transform_keys(&:to_s)
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

  def normalize_service_party_name(value)
    value.to_s.strip.presence
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

  def total_due_in_currency(venta, currency, tasa_dolar, calculated_totals: nil)
    totals = calculated_totals || calculated_sale_totals_for(venta)
    return totals[:total_usd] unless currency == "VES"

    return totals[:total_base] if venta.base_currency.to_s.upcase == "VES"

    rate = tasa_dolar.to_d
    return 0.to_d unless rate.positive?

    (totals[:total_usd] * rate).round(2)
  end

  def parsed_totals_payload(raw_totals)
    source = raw_totals.respond_to?(:to_h) ? raw_totals.to_h : {}
    return {} if source.blank?

    {
      taxable_subtotal_base: parse_decimal(source[:taxable_subtotal_base] || source["taxable_subtotal_base"],
                                           default: 0).to_d.round(2),
      exento_subtotal_base: parse_decimal(source[:exento_subtotal_base] || source["exento_subtotal_base"],
                                          default: 0).to_d.round(2),
      vat_base: parse_decimal(source[:vat_base] || source["vat_base"], default: 0).to_d.round(2),
      total_base: parse_decimal(source[:total_base] || source["total_base"], default: 0).to_d.round(2),
    }
  end

  def calculated_sale_totals_for(venta)
    active_items = venta.venta_items.reject(&:marked_for_destruction?)
    taxable_items = active_items.reject { |item| item_exento_for_vat?(item) }
    exento_items = active_items.select { |item| item_exento_for_vat?(item) }
    vat_rate = venta.vat_rate.to_d

    taxable_subtotal_usd = taxable_items.sum { |item| item.subtotal_usd.to_d }.round(2)
    exento_subtotal_usd = exento_items.sum { |item| item.subtotal_usd.to_d }.round(2)
    vat_usd = venta.vat_mode == "none" ? 0.to_d : (taxable_subtotal_usd * vat_rate).round(2)
    total_usd = (taxable_subtotal_usd + exento_subtotal_usd + vat_usd).round(2)

    if venta.base_currency.to_s.upcase == "VES"
      taxable_subtotal_base = taxable_items.sum { |item| venta.base_line_subtotal(item) }.round(2)
      exento_subtotal_base = exento_items.sum { |item| venta.base_line_subtotal(item) }.round(2)
      vat_base = venta.vat_mode == "none" ? 0.to_d : (taxable_subtotal_base * vat_rate).round(2)
      total_base = (taxable_subtotal_base + exento_subtotal_base + vat_base).round(2)
    else
      taxable_subtotal_base = taxable_subtotal_usd
      exento_subtotal_base = exento_subtotal_usd
      vat_base = vat_usd
      total_base = total_usd
    end

    {
      taxable_subtotal_usd: taxable_subtotal_usd,
      exento_subtotal_usd: exento_subtotal_usd,
      vat_usd: vat_usd,
      total_usd: total_usd,
      taxable_subtotal_base: taxable_subtotal_base,
      exento_subtotal_base: exento_subtotal_base,
      vat_base: vat_base,
      total_base: total_base,
    }
  end

  def validate_client_totals_against_server(client_totals:, server_totals:, tolerance:)
    checks = {
      taxable_subtotal_base: "subtotal gravado",
      exento_subtotal_base: "subtotal exento",
      vat_base: "IVA",
      total_base: "total",
    }

    checks.each do |key, label|
      client_value = client_totals[key].to_d.round(2)
      server_value = server_totals[key].to_d.round(2)
      delta = (client_value - server_value).abs
      next unless delta > tolerance.to_d

      return "Los calculos del #{label} no coinciden con el servidor. Actualiza la orden y vuelve a cobrar."
    end

    nil
  end

  def item_exento_for_vat?(item)
    if item.respond_to?(:exento) && !item.exento.nil?
      ActiveModel::Type::Boolean.new.cast(item.exento)
    else
      item.producto.present? && item.producto.respond_to?(:exento?) && item.producto.exento?
    end
  end

  def valid_reference?(value)
    value.to_s.match?(/\A\d{4}\z/)
  end

  def build_movement_description(venta, row, label)
    "#{label} venta ##{venta.id} [VENTA:#{venta.id}]"
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

  def normalize_cashea_sale_payload(raw_payload)
    source = raw_payload.respond_to?(:to_h) ? raw_payload.to_h : {}
    enabled_value = source['enabled'] || source[:enabled]
    account_id_value = source['account_id'] || source[:account_id]
    initial_usd_value = source['initial_usd'] || source[:initial_usd]
    min_purchase_value = source['min_purchase_usd'] || source[:min_purchase_usd]

    {
      enabled: ActiveModel::Type::Boolean.new.cast(enabled_value),
      account_id: account_id_value.to_i,
      initial_usd: parse_decimal(initial_usd_value, default: 0).to_d.round(2),
      min_purchase_usd: parse_decimal(min_purchase_value, default: 0).to_d.round(2),
      account: nil,
      line_mode: nil,
      installments: 0,
      custom_installments: [],
    }
  end

  def normalize_cashea_installments_payload(raw_payload)
    source = raw_payload.respond_to?(:to_h) ? raw_payload.to_h : {}
    rows = source['installments'] || source[:installments]

    Array(rows).filter_map do |row|
      entry = row.respond_to?(:to_h) ? row.to_h : {}
      amount_value = entry['amount_usd'] || entry[:amount_usd]
      due_on_value = entry['due_on'] || entry[:due_on]
      amount_usd = parse_decimal(amount_value, default: 0).to_d.round(2)
      due_on = parse_payment_date(due_on_value)
      next if amount_usd <= 0 || due_on.blank?

      {
        amount_usd: amount_usd,
        due_on: due_on,
      }
    end
  end

  def default_first_due_on_for_cashea(account)
    today = Time.use_zone("America/Caracas") { Time.zone.today }
    return today + 30.days if account&.cashea_line_mode.to_s == 'principal'

    today + 15.days
  end

  def create_cashea_receivable_installments_for_sale!(venta:, account:, total_amount_usd:, first_due_on: nil, custom_installments: nil)
    installments = account&.cashea_installments_count.to_i
    installments = 1 if installments <= 0

    due_on = first_due_on || default_first_due_on_for_cashea(account)
    due_on = Time.use_zone("America/Caracas") { Time.zone.today } if due_on.blank?

    cashea_debtor = find_or_create_cashea_debtor!
    owner_label = venta.cliente&.name.to_s.strip.presence || "Cliente sin nombre"
    group_token = sale_debt_group_token_for(cliente_id: cashea_debtor.id, currency: 'USD')

    installment_plan = if Array(custom_installments).any?
        Array(custom_installments).each_with_index.map do |row, index|
          {
            amount: row[:amount_usd].to_d.round(2),
            due_on: row[:due_on],
            number: index + 1,
          }
        end
      else
        installment_amounts = split_amount_into_installments(total_amount_usd.to_d, installments)
        installment_amounts.each_with_index.map do |installment_amount, index|
          {
            amount: installment_amount,
            due_on: due_on >> index,
            number: index + 1,
          }
        end
      end

    total_installments = installment_plan.size

    installment_plan.each do |installment|
      installment_amount = installment[:amount]
      installment_due_on = installment[:due_on]
      installment_number = installment[:number]

      debt_attrs = {
        name: "Cuota Cashea #{installment_number}/#{total_installments} - #{owner_label}",
        description: "Cuota Cashea #{installment_number}/#{total_installments} cliente #{owner_label} pendiente venta ##{venta.id} [CLIENTE_DUENO:#{owner_label}] [VENTA:#{venta.id}]",
        debt_kind: 'receivable',
        amount: installment_amount,
        currency: 'USD',
        issued_on: Time.use_zone("America/Caracas") { Time.zone.today },
        due_on: installment_due_on,
        cliente: cashea_debtor,
        venta: venta,
      }
      debt_attrs[:group_token] = group_token if Debt.column_names.include?('group_token')

      current_business.debts.create!(debt_attrs)
    end
  end

  def find_or_create_cashea_debtor!
    existing = current_business.clientes.where("LOWER(name) = ?", "cashea").first
    return existing if existing.present?

    current_business.clientes.create!(
      document_type: 'J',
      document_number: "CASHEA-#{current_business.id}",
      name: 'Cashea',
      phone: '0000000000',
      address: 'Deudor interno para cuotas Cashea',
    )
  end

  def split_amount_into_installments(total, installments)
    normalized_total = total.to_d.round(2)
    return [normalized_total] if installments <= 1

    base_amount = (normalized_total / installments).round(2)
    values = Array.new(installments, base_amount)
    delta = (normalized_total - values.sum).round(2)
    values[-1] = (values[-1] + delta).round(2)
    values
  end

  def normalize_checkout_discount_payload(raw_payload)
    source = raw_payload.respond_to?(:to_h) ? raw_payload.to_h : {}
    enabled_value = source["enabled"] || source[:enabled]
    amount_value = source["amount"] || source[:amount]
    reason_value = source["reason"] || source[:reason]

    enabled = ActiveModel::Type::Boolean.new.cast(enabled_value)
    amount = parse_decimal(amount_value, default: 0).to_d.round(2)
    reason = normalize_checkout_discount_reason(reason_value)

    {
      enabled: enabled,
      amount: amount,
      reason: reason,
    }
  end

  def normalize_checkout_discount_reason(raw_reason)
    normalized = raw_reason.to_s.strip.downcase
    allowed = %w[exoneracion_de_faltante oferta_por_compra]
    return normalized if allowed.include?(normalized)

    nil
  end

  def convert_checkout_discount_to_currency(amount:, from_currency:, to_currency:, tasa_dolar:)
    convert_payment_to_currency(amount, from_currency, to_currency, tasa_dolar)
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

  def load_sale_service_cost_breakdown_context!
    notes_rows = sale_service_cost_rows_from_notes(@venta)
    debt_rows = sale_service_cost_rows_from_debts(@venta)
    printing_rows = sale_service_printing_rows_from_notes(@venta)

    notes_by_name = notes_rows.group_by { |row| normalized_sale_service_cost_row_key(row["service_name"]) }
    debt_by_name = debt_rows.group_by { |row| normalized_sale_service_cost_row_key(row["service_name"]) }

    merged_rows = []
    (notes_by_name.keys | debt_by_name.keys).each do |key|
      rows = debt_by_name[key].presence || notes_by_name[key] || []
      merged_rows.concat(rows)
    end

    hydrate_invoice_breakdown_visibility!(rows: merged_rows)

    @sale_service_cost_rows_by_name = merged_rows.each_with_object(Hash.new { |hash, k| hash[k] = [] }) do |row, hash|
      key = normalized_sale_service_cost_row_key(row["service_name"])
      next if key.blank?

      hash[key] << row
    end

    @sale_service_printings_by_parent_name = printing_rows.each_with_object(Hash.new do |hash, k|
      hash[k] = []
    end) do |row, hash|
      key = normalized_sale_service_cost_row_key(row["parent_service_name"])
      next if key.blank?

      hash[key] << row
    end
  end

  def sale_service_cost_rows_from_notes(venta)
    notes_payload = parse_notes_payload(venta.notes)
    Array(notes_payload["service_cost_settlements"]).filter_map do |row|
      next unless row.is_a?(Hash)

      normalized = row.deep_stringify_keys
      normalized["detail_lines"] = normalize_service_cost_lines_payload(normalized["detail_lines"])
      normalized
    end
  end

  def sale_service_printing_rows_from_notes(venta)
    notes_payload = parse_notes_payload(venta.notes)
    Array(notes_payload["sold_service_printings"]).filter_map do |row|
      next unless row.is_a?(Hash)

      normalized = row.deep_stringify_keys
      invoice_breakdown_only = ActiveModel::Type::Boolean.new.cast(normalized["invoice_breakdown_only"])
      total_sale_price_usd = normalized["total_sale_price_usd"].to_d.round(2)
      next unless total_sale_price_usd.positive? || invoice_breakdown_only

      quantity = normalized["quantity"].to_d.round(2)
      quantity = 1.to_d unless quantity.positive?

      rate = @sale_reference[:effective_usd_rate].to_d
      rate = venta.tasa_dolar.to_d unless rate.positive?

      unit_sale_price_bs = normalized["unit_sale_price_bs"].to_d.round(2)
      total_sale_price_bs = normalized["total_sale_price_bs"].to_d.round(2)

      if normalized["classification"].to_s == "physical_delivery_extra_product" &&
         !total_sale_price_usd.positive? &&
         normalized["product_id"].to_i.positive?
        product = current_business.productos.find_by(id: normalized["product_id"].to_i)
        if product
          unit_sale_price_usd = product.precio_venta_usd.to_d.round(2)
          total_sale_price_usd = (unit_sale_price_usd * quantity).round(2)
          unit_sale_price_bs = (unit_sale_price_usd * rate).round(2) if rate.positive?
          total_sale_price_bs = (total_sale_price_usd * rate).round(2) if rate.positive?
        end
      end

      if !unit_sale_price_bs.positive? && rate.positive?
        unit_sale_price_bs = ((total_sale_price_usd / quantity) * rate).round(2)
      end

      total_sale_price_bs = (total_sale_price_usd * rate).round(2) if !total_sale_price_bs.positive? && rate.positive?

      normalized.merge(
        "classification" => normalized["classification"].to_s.presence || (invoice_breakdown_only ? "physical_delivery_extra_product" : "printing_service"),
        "classification_label" => normalized["classification_label"].to_s.presence || (invoice_breakdown_only ? "Producto adicional de entrega" : "Servicio de impresion"),
        "quantity" => quantity.to_f,
        "unit_sale_price_bs" => unit_sale_price_bs.to_f,
        "total_sale_price_bs" => total_sale_price_bs.to_f,
        "unit_sale_price_usd" => (total_sale_price_usd.positive? ? (total_sale_price_usd / quantity).round(2) : normalized["unit_sale_price_usd"].to_d.round(2)).to_f,
        "total_sale_price_usd" => total_sale_price_usd.to_f,
      )
    end
  end

  def sale_service_cost_rows_from_debts(venta)
    debts = current_business
      .debts
      .where(venta_id: venta.id, debt_kind: "payable")
      .where("description LIKE ?", "%[SERVICE_COST]%")
      .includes(service: [
                  { service_expense_structures: [{ service_manager_expenses: :manager }] },
                  { service_expense_structures: :service_variable_expenses },
                  { service_expense_structures: { service_product_expenses: %i[producto product_variation] } },
                ])
      .order(:id)

    debts.map do |debt|
      details = debt.service_cost_details_hash
      {
        "service_id" => debt.service_id,
        "service_name" => details["service_name"].to_s.strip.presence || debt.service&.description.to_s,
        "detail_lines" => sale_service_cost_lines_for_invoice(debt: debt),
      }
    end
  end

  def sale_service_cost_lines_for_invoice(debt:)
    stored_lines = debt.service_cost_lines
    return stored_lines unless debt.service_cost_pending?
    return stored_lines if debt.service.blank?

    live_lines = build_live_service_cost_lines_for_invoice(debt: debt)
    return stored_lines if live_lines.blank?

    apply_paid_amounts_to_live_sale_service_cost_lines(
      live_lines: live_lines,
      stored_lines: stored_lines,
    )
  end

  def build_live_service_cost_lines_for_invoice(debt:)
    service = debt.service
    return [] if service.blank?

    quantity = debt.service_cost_details_hash["quantity"].to_d
    quantity = 1.to_d unless quantity.positive?

    tasa_dolar = TasaCambio.latest_value("Dolar BCV").to_d
    unidad_vi = TasaCambio.latest_value("Unidad VI").to_d

    normalize_service_cost_lines_payload(
      build_service_cost_detail_lines(
        service: service,
        multiplier: quantity,
        tasa_dolar: tasa_dolar,
        unidad_vi: unidad_vi,
        consumable_decisions: {},
      )
    )
  end

  def apply_paid_amounts_to_live_sale_service_cost_lines(live_lines:, stored_lines:)
    stored_by_source = Array(stored_lines).each_with_object({}) do |raw_line, hash|
      line = raw_line.deep_stringify_keys
      key = sale_service_cost_line_source_key(line)
      next if key.blank?

      hash[key] ||= []
      hash[key] << line
    end

    Array(live_lines).map do |raw_line|
      line = raw_line.deep_stringify_keys
      key = sale_service_cost_line_source_key(line)
      stored_line = key.present? ? stored_by_source[key]&.shift : nil

      amount_usd = line["amount_usd"].to_d.round(2)
      paid_usd = stored_line.to_h["paid_usd"].to_d.round(2)
      paid_usd = amount_usd if paid_usd > amount_usd

      pending_usd = (amount_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      line["paid_usd"] = paid_usd.to_f
      line["pending_usd"] = pending_usd.to_f
      line["status"] = if pending_usd <= 0
          "paid"
        elsif paid_usd.positive?
          "partial"
        else
          "pending"
        end

      line
    end
  end

  def sale_service_cost_line_source_key(line)
    source_type = line["source_type"].to_s
    source_id = line["source_id"].to_s
    return "" if source_type.blank? || source_id.blank?

    "#{source_type}:#{source_id}"
  end

  def normalized_sale_service_cost_row_key(service_name)
    service_name.to_s.strip.downcase
  end

  def hydrate_invoice_breakdown_visibility!(rows:)
    source_ids = Array(rows).flat_map do |row|
      Array(row["detail_lines"]).filter_map do |line|
        next unless line.is_a?(Hash)
        next unless line["classification"].to_s == "product_expense"
        next unless line["source_type"].to_s == "ServiceProductExpense"

        source_id = line["source_id"].to_i
        source_id if source_id.positive?
      end
    end.uniq

    breakdown_by_id = if source_ids.empty?
        {}
      else
        ServiceProductExpense.where(id: source_ids).pluck(:id, :breakdown_in_invoice).to_h
      end

    Array(rows).each do |row|
      Array(row["detail_lines"]).each do |line|
        next unless line.is_a?(Hash)
        next unless line["classification"].to_s == "product_expense"

        explicit_flag = line["breakdown_in_invoice"]
        visible = if explicit_flag.nil?
            source_id = line["source_id"].to_i
            source_id.positive? ? ActiveModel::Type::Boolean.new.cast(breakdown_by_id[source_id]) : false
          else
            ActiveModel::Type::Boolean.new.cast(explicit_flag)
          end

        line["breakdown_in_invoice"] = visible
      end
    end
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
    normalized_currency = currency.to_s.upcase

    debt_attrs = {
      name: "Saldo venta ##{venta.id}",
      description: "Saldo pendiente venta ##{venta.id} [VENTA:#{venta.id}]",
      debt_kind: "receivable",
      amount: amount.to_d.round(2),
      currency: normalized_currency,
      issued_on: issued_on,
      due_on: due_on,
      cliente: venta.cliente,
      venta: venta,
    }

    if Debt.column_names.include?("group_token")
      debt_attrs[:group_token] = sale_debt_group_token_for(
        cliente_id: venta.cliente_id,
        currency: normalized_currency,
      )
    end

    current_business.debts.create!(debt_attrs)
  end

  def sale_debt_group_token_for(cliente_id:, currency:)
    return generated_sale_group_token if cliente_id.blank?

    active_debts = current_business
                   .debts
                   .excluding_service_cost_records
                   .where(debt_kind: "receivable", cliente_id: cliente_id, currency: currency)
                   .includes(:debt_payments)
                   .select { |debt| debt.balance.to_d > 0.01.to_d }

    latest_token = active_debts
                   .sort_by { |debt| [debt.issued_on || Date.new(1970, 1, 1), debt.created_at || Time.zone.at(0), debt.id.to_i] }
                   .reverse
                   .map { |debt| debt.group_token.to_s.strip }
                   .find(&:present?)

    latest_token.presence || generated_sale_group_token
  end

  def generated_sale_group_token
    "grp_#{SecureRandom.hex(10)}"
  end

  def service_cost_debit_enabled?(service)
    return false unless service

    service.cost?
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

  def normalize_service_delivery_presentation(value, service: nil)
    normalized = value.to_s.strip.downcase
    return normalized if %w[physical digital].include?(normalized)

    physical_enabled = effective_delivery_physical_enabled_for_sale(service)
    digital_enabled = effective_delivery_digital_enabled_for_sale(service)

    return "physical" if physical_enabled && !digital_enabled

    return "digital" if digital_enabled && !physical_enabled

    nil
  end

  def normalize_print_delivery_pages_for_sale(service)
    config = effective_rcv_service_config_for_sale(service)
    source_pages = config[:print_delivery_pages]
    source_pages = service&.print_delivery_pages if source_pages.blank?
    fallback_print_type_service_id = config[:print_delivery_service_id].presence || service&.print_delivery_service_id
    fallback_material_surcharge_id = config[:print_delivery_material_surcharge_id].presence || service&.print_delivery_material_surcharge_id

    Array(source_pages).filter_map do |raw_page|
      row = raw_page.is_a?(Hash) ? raw_page.deep_stringify_keys : {}
      coverage = row["coverage_percent"].to_d.round(2)
      next unless coverage.positive?

      print_type_service_id = row["print_type_service_id"].to_i
      if print_type_service_id <= 0 && fallback_print_type_service_id.present?
        print_type_service_id = fallback_print_type_service_id.to_i
      end

      material_surcharge_id = row["material_surcharge_id"].to_i
      if material_surcharge_id <= 0 && fallback_material_surcharge_id.present?
        material_surcharge_id = fallback_material_surcharge_id.to_i
      end
      next unless print_type_service_id.positive? && material_surcharge_id.positive?

      includes_lamination = ActiveModel::Type::Boolean.new.cast(row["includes_lamination"])
      lamination_service_id = row["lamination_service_id"].to_i
      lamination_service_id = nil unless includes_lamination && lamination_service_id.positive?

      {
        "page_number" => row["page_number"].to_i.positive? ? row["page_number"].to_i : 1,
        "coverage_percent" => coverage,
        "print_type_service_id" => print_type_service_id,
        "material_surcharge_id" => material_surcharge_id,
        "includes_lamination" => includes_lamination,
        "lamination_service_id" => lamination_service_id,
      }
    end.sort_by { |row| row["page_number"].to_i }
  end

  def normalize_print_delivery_extra_products_for_sale(service)
    return [] unless effective_delivery_physical_enabled_for_sale(service)

    config = effective_rcv_service_config_for_sale(service)
    rows = config[:print_delivery_extra_products]
    rows = service.normalized_print_delivery_extra_products if rows.blank? && service.respond_to?(:normalized_print_delivery_extra_products)
    return [] unless rows.is_a?(Array)

    product_ids = rows.filter_map do |row|
      product_id = row.is_a?(Hash) ? row["product_id"].to_i : 0
      product_id if product_id.positive?
    end.uniq

    products_by_id = current_business
      .productos
      .where(id: product_ids)
      .index_by(&:id)

    rows.filter_map do |raw_row|
      row = raw_row.is_a?(Hash) ? raw_row.deep_stringify_keys : {}
      product_id = row["product_id"].to_i
      variation_id = row["variation_id"].to_i
      quantity = row["quantity"].to_d.round(2)
      next unless product_id.positive? && quantity.positive?

      product = products_by_id[product_id]
      next unless product

      variation = product.product_variations.find { |item| item.id == variation_id }
      variation ||= product.product_variations.min_by(&:id)
      next unless variation

      {
        product_id: product.id,
        product_name: product.descripcion.to_s,
        variation_id: variation.id,
        variation_name: variation.description.to_s,
        quantity: quantity.to_f,
        breakdown_in_invoice: ActiveModel::Type::Boolean.new.cast(row["breakdown_in_invoice"]),
      }
    end
  end

  def resolve_printing_price_bs_for_coverage(coverage_percent:, prices:)
    sorted = Array(prices).sort_by { |row| row.coverage_percent.to_d }
    return 0.to_d if sorted.empty?

    match = sorted.find { |row| row.coverage_percent.to_d >= coverage_percent.to_d }
    match ||= sorted.last
    match&.price_bs.to_d
  end

  def build_service_physical_printing_payload(service:, tasa_dolar:)
    return { enabled: false } unless effective_delivery_physical_enabled_for_sale(service)

    pages = normalize_print_delivery_pages_for_sale(service)
    return { enabled: false } if pages.empty?

    type_service_ids = pages.map { |row| row["print_type_service_id"].to_i }.uniq
    material_ids = pages.map { |row| row["material_surcharge_id"].to_i }.uniq
    lamination_ids = pages.filter_map do |row|
      row["lamination_service_id"].to_i if row["lamination_service_id"].to_i.positive?
    end.uniq

    type_services_by_id = current_business
      .services
      .includes(:service_print_coverage_prices)
      .where(id: type_service_ids)
      .index_by(&:id)
    material_rows_by_id = ServicePrintMaterialSurcharge
      .includes(:producto)
      .where(id: material_ids)
      .index_by(&:id)
    lamination_services_by_id = current_business
      .services
      .includes(service_print_material_surcharges: :producto)
      .where(id: lamination_ids)
      .index_by(&:id)

    lamination_material_ids = lamination_services_by_id.values.flat_map do |lamination_service|
      lamination_service.service_print_material_surcharges.map(&:id)
    end
    if lamination_material_ids.any?
      material_rows_by_id.merge!(
        ServicePrintMaterialSurcharge
          .includes(:producto)
          .where(id: lamination_material_ids)
          .index_by(&:id)
      )
    end

    normalized_pages = []
    grouped_material_usage = Hash.new(0)
    grouped_lamination_usage = Hash.new(0)
    cost_bs = 0.to_d

    pages.each do |row|
      type_service = type_services_by_id[row["print_type_service_id"].to_i]
      next if type_service.blank?

      prices = type_service.service_print_coverage_prices.ordered_by_coverage.to_a
      next if prices.empty?

      material_row = material_rows_by_id[row["material_surcharge_id"].to_i]
      next if material_row.blank? || material_row.service_id != type_service.id || material_row.producto.blank?

      page_cost_bs = resolve_printing_price_bs_for_coverage(coverage_percent: row["coverage_percent"].to_d,
                                                            prices: prices)
      cost_bs += page_cost_bs.to_d

      grouped_material_usage[material_row.id] += 1

      if ActiveModel::Type::Boolean.new.cast(row["includes_lamination"])
        lamination_service = lamination_services_by_id[row["lamination_service_id"].to_i]
        if lamination_service.present?
          grouped_lamination_usage[lamination_service.id] += 1
          lamination_service.service_print_material_surcharges.each do |lamination_material_row|
            next if lamination_material_row.producto.blank?

            required_quantity = lamination_material_row.respond_to?(:required_quantity) ? lamination_material_row.required_quantity.to_d : 1.to_d
            grouped_material_usage[lamination_material_row.id] += required_quantity
          end
        end
      end

      normalized_pages << {
        page_number: row["page_number"].to_i,
        coverage_percent: row["coverage_percent"].to_d.to_f,
        print_type_service_id: type_service.id,
        print_type_service_name: type_service.description.to_s,
        material_surcharge_id: material_row.id,
        material_label: material_row.display_label.to_s,
        material_product_id: material_row.producto_id,
        material_product_name: material_row.producto&.descripcion.to_s,
        includes_lamination: ActiveModel::Type::Boolean.new.cast(row["includes_lamination"]),
        lamination_service_id: row["lamination_service_id"].to_i.positive? ? row["lamination_service_id"].to_i : nil,
        lamination_service_name: lamination_services_by_id[row["lamination_service_id"].to_i]&.description.to_s,
        page_cost_bs: page_cost_bs.to_d.round(2).to_f,
      }
    end

    return { enabled: false } if normalized_pages.empty?

    cost_bs = cost_bs.round(2)
    cost_usd = if tasa_dolar.to_d.positive?
        (cost_bs / tasa_dolar.to_d).round(2)
      else
        0.to_d
      end

    material_rows = grouped_material_usage.filter_map do |surcharge_id, quantity|
      row = material_rows_by_id[surcharge_id]
      next if row.blank? || row.producto.blank?

      {
        surcharge_id: row.id,
        label: row.display_label.to_s,
        product_id: row.producto_id,
        product_name: row.producto&.descripcion.to_s,
        quantity: quantity.to_i,
      }
    end

    lamination_rows = grouped_lamination_usage.filter_map do |lamination_service_id, quantity|
      lamination_service = lamination_services_by_id[lamination_service_id]
      next if lamination_service.blank?

      {
        service_id: lamination_service.id,
        service_name: lamination_service.print_sale_display_name.to_s.presence || lamination_service.description.to_s,
        quantity: quantity.to_i,
        material_rows: lamination_service.service_print_material_surcharges.filter_map do |row|
          next if row.producto.blank?

          required_quantity = row.respond_to?(:required_quantity) ? row.required_quantity.to_d : 1.to_d

          {
            surcharge_id: row.id,
            label: row.display_label.to_s,
            product_id: row.producto_id,
            product_name: row.producto&.descripcion.to_s,
            quantity: required_quantity.to_f,
          }
        end,
      }
    end

    first_material = material_rows.first
    extra_products = normalize_print_delivery_extra_products_for_sale(service)

    {
      enabled: cost_bs.positive?,
      pages: normalized_pages,
      material_rows: material_rows,
      extra_products: extra_products,
      lamination_rows: lamination_rows,
      material: first_material,
      cost_bs: cost_bs.to_f,
      cost_usd: cost_usd.to_f,
    }
  end

  def effective_rcv_service_config_for_sale(service)
    return {} if service.blank? || !service.respond_to?(:rcv_service?) || !service.rcv_service?

    @effective_rcv_service_config ||= begin
        attrs = Service.rcv_shared_template_attributes_for_business(current_business)
        attrs = attrs.to_h if attrs.respond_to?(:to_h)
        attrs.deep_symbolize_keys
      rescue StandardError
        {}
      end
  end

  def effective_delivery_physical_enabled_for_sale(service)
    config = effective_rcv_service_config_for_sale(service)
    source_value = config.key?(:delivery_physical_enabled) ? config[:delivery_physical_enabled] : service&.delivery_physical_enabled
    ActiveModel::Type::Boolean.new.cast(source_value)
  end

  def effective_delivery_digital_enabled_for_sale(service)
    config = effective_rcv_service_config_for_sale(service)
    source_value = config.key?(:delivery_digital_enabled) ? config[:delivery_digital_enabled] : service&.delivery_digital_enabled
    ActiveModel::Type::Boolean.new.cast(source_value)
  end
end
