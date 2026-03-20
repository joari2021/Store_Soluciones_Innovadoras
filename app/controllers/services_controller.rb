class ServicesController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:services) }
  before_action :require_admin, except: %i[index show]
  before_action :set_service, only: %i[show edit update destroy]
  before_action :set_form_collections, only: %i[new create edit update]
  before_action :set_pending_cost_accounts, only: %i[pending_costs pending_cost_detail pay_pending_cost_line]

  def index
    scoped_services = current_business
      .services
      .includes(:system_service, service_expense_structures: %i[
                                   service_variable_expenses
                                 ] + [
                                   { service_manager_expenses: :manager },
                                   { service_nested_expenses: :nested_service },
                                   { service_product_expenses: [:product_variation, { producto: :product_variations }] },
                                 ])
    scoped_services = scoped_services.visible_for_user(Current.user)

    @services = if params[:query_text].present?
        scoped_services
          .joins(:system_service)
          .whose_name_starts_with(params[:query_text])
      else
        scoped_services
          .order("system_services.name ASC, services.description ASC")
      end

    @pagy, @services = pagy_countless(@services, items: 24)
  end

  def pending_costs
    @pending_cost_filters = pending_cost_filters_from_params
    @pending_cost_managers = Manager.order(:name)
    @pending_cost_system_services = SystemService
      .joins(:services)
      .where(services: { business_id: current_business.id })
      .distinct
      .order(:name)

    sales_scope = current_business
      .ventas
      .where(status: "paid")
      .includes(:service_cost_debts, :venta_items)
      .order(created_at: :desc)

    sales_scope = apply_pending_cost_sales_date_filters(scope: sales_scope, filters: @pending_cost_filters)

    sold_rows = build_pending_cost_sold_service_rows_for_sales(sales: sales_scope.to_a)
    sold_rows = filter_pending_cost_sold_rows(rows: sold_rows, filters: @pending_cost_filters)
    sold_rows.sort_by! do |row|
      [
        -(row[:sold_at]&.to_i || 0),
        row[:sale_id].to_i,
        row[:parent_service_name].to_s.downcase,
        (row[:nested_sale] ? 1 : 0),
      ]
    end

    @pending_cost_total_rows = sold_rows.size
    @pending_cost_pending_count = sold_rows.count { |row| row[:cost_status] == "pending" }
    @pending_cost_partial_count = sold_rows.count { |row| row[:cost_status] == "partial" }
    @pending_cost_paid_count = sold_rows.count { |row| row[:cost_status] == "paid" }
    @pending_cost_no_cost_count = sold_rows.count { |row| row[:cost_status] == "no_cost" }
    @pending_cost_pending_total = sold_rows.sum { |row| row[:pending_cost_usd].to_d }.round(2)

    @pending_cost_rows = paginate_pending_cost_sold_rows(rows: sold_rows)
  end

  def pending_cost_detail
    debt = current_business
      .debts
      .includes(:service, :venta, :debt_payments)
      .find_by(id: params[:debt_id])

    unless debt&.payable?
      return redirect_to pending_costs_services_path,
                         alert: "No se encontro el registro de costo pendiente indicado."
    end

    lines = normalized_pending_cost_lines_for(debt)
    if lines.empty?
      return redirect_to pending_costs_services_path,
                         alert: "No hay detalles de costo disponibles para este registro."
    end

    pending_usd = lines.sum { |line| line["pending_usd"].to_d }.round(2)
    paid_usd = lines.sum { |line| line["paid_usd"].to_d }.round(2)
    total_usd = lines.sum { |line| line["amount_usd"].to_d }.round(2)

    @pending_cost_row = {
      debt: debt,
      lines: lines,
      debt_currency: debt.currency.to_s.upcase,
      total_usd: total_usd,
      paid_usd: paid_usd,
      pending_usd: pending_usd,
      status: pending_cost_status_from_lines(lines),
    }

    @pending_cost_currency_rates = build_pending_cost_currency_rates(rows: [@pending_cost_row],
                                                                     accounts: @pending_cost_accounts)
  end

  def pending_cost_rates
    reference_date = parse_pending_cost_payment_date(params[:fecha] || params[:date])
    return render json: { error: "Fecha invalida" }, status: :unprocessable_entity if reference_date.blank?

    rates = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: reference_date).to_d.to_f
    end
    rates["VES"] = 1.0

    render json: {
      fecha_referencia: reference_date,
      rates: rates,
    }, status: :ok
  end

  def pay_pending_cost_line
    debt = current_business
      .debts
      .includes(:service, :debt_payments)
      .find_by(id: params[:debt_id])

    redirect_path = pending_cost_redirect_path(debt: debt)

    unless debt&.payable? && debt.service_cost_pending?
      return redirect_to pending_costs_services_path,
                         alert: "No se encontro la deuda pendiente de costos indicada."
    end

    line_id = params[:line_id].to_s.strip
    lines = normalized_pending_cost_lines_for(debt)
    line = lines.find { |row| row["line_id"].to_s == line_id }

    if line.blank?
      return redirect_to redirect_path,
                         alert: "No se encontro la clasificacion/estructura seleccionada."
    end

    pending_line_usd = line["pending_usd"].to_d.round(2)
    unless pending_line_usd.positive?
      return redirect_to redirect_path,
                         alert: "La linea seleccionada ya se encuentra pagada."
    end

    account = @pending_cost_accounts.find_by(id: params[:account_id])
    if account.blank?
      return redirect_to redirect_path,
                         alert: "Selecciona una cuenta valida para registrar el pago."
    end

    required_account_currency = pending_cost_expected_account_currency_for(
      line: line,
      debt_currency: debt.currency,
    )
    if required_account_currency.present? && account.currency.to_s.upcase != required_account_currency
      required_label = pending_cost_expected_account_currency_label(required_account_currency)
      return redirect_to redirect_path,
                         alert: "Esta clasificacion solo permite pagos con cuentas en #{required_label}."
    end

    amount_original = parse_pending_cost_decimal(params[:amount])
    unless amount_original.positive?
      return redirect_to redirect_path,
                         alert: "Indica un monto valido mayor a 0."
    end

    payment_date = parse_pending_cost_payment_date(params[:payment_date])
    if payment_date.blank?
      return redirect_to redirect_path,
                         alert: "Debes indicar una fecha valida para registrar el pago."
    end

    payment_method = params[:payment_method].to_s.strip
    reference = params[:reference].to_s.strip

    if account.account_type == "bank_account"
      unless %w[transfer mobile].include?(payment_method)
        return redirect_to redirect_path,
                           alert: "Selecciona transferencia o pago movil para pagos bancarios."
      end

      unless /^\d{6}$/.match?(reference)
        return redirect_to redirect_path,
                           alert: "La referencia bancaria debe tener exactamente 6 digitos."
      end
    else
      payment_method = nil
      reference = nil
    end

    conversion = CurrencyConverter.convert(
      amount: amount_original,
      from_currency: account.currency,
      to_currency: debt.currency,
      on_date: payment_date,
    )

    if conversion.blank?
      return redirect_to redirect_path,
                         alert: "No se pudo convertir el pago a la moneda de la deuda."
    end

    amount_in_debt_currency = conversion[:amount].to_d.round(2)
    payment_scope = params[:payment_scope].to_s
    force_total_settlement = ActiveModel::Type::Boolean.new.cast(params[:force_total_settlement]) ||
                             payment_scope == "total"

    if !force_total_settlement && amount_in_debt_currency > pending_line_usd + 0.01.to_d
      return redirect_to redirect_path,
                         alert: "El pago excede el saldo pendiente de la clasificacion seleccionada."
    end

    update_source_cost_override = params[:update_source_cost_override]
    update_source_cost = if update_source_cost_override.present?
        ActiveModel::Type::Boolean.new.cast(update_source_cost_override)
      else
        ActiveModel::Type::Boolean.new.cast(params[:update_source_cost])
      end

    amount_applied_to_line = force_total_settlement ? pending_line_usd : amount_in_debt_currency

    Debt.transaction do
      payment = debt.debt_payments.create!(
        account: account,
        amount: amount_original,
        currency: account.currency,
        payment_method: payment_method,
        reference: reference,
        occurred_at: payment_date,
        notes: "Pago costo servicio [DEBT:#{debt.id}] [LINE:#{line_id}]",
      )

      if force_total_settlement
        effective_rate = if amount_original.to_d.positive?
            (amount_applied_to_line / amount_original.to_d).round(8)
          else
            payment.exchange_rate_to_debt_currency.to_d
          end

        payment.update_columns(
          amount_in_debt_currency: amount_applied_to_line.to_d,
          exchange_rate_to_debt_currency: effective_rate,
          updated_at: Time.current,
        )
      end

      line["paid_usd"] = (line["paid_usd"].to_d + amount_applied_to_line).round(2).to_f
      line["pending_usd"] = (line["amount_usd"].to_d - line["paid_usd"].to_d).round(2).to_f
      line["pending_usd"] = 0.0 if line["pending_usd"].to_d.abs <= 0.01.to_d
      line["status"] = if line["pending_usd"].to_d <= 0
          "paid"
        elsif line["paid_usd"].to_d.positive?
          "partial"
        else
          "pending"
        end

      if update_source_cost
        source_snapshot = update_pending_cost_source_row!(
          line: line,
          amount_usd: amount_applied_to_line,
          paid_amount_original: amount_original,
          paid_currency: account.currency,
          on_date: payment_date,
        )
        apply_pending_cost_source_snapshot!(line: line, snapshot: source_snapshot, debt: debt)
      else
        lock_paid_pending_cost_line_snapshot!(
          line: line,
          paid_amount_original: amount_original,
          paid_currency: account.currency,
          on_date: payment_date,
        )
      end

      paid_usd = lines.sum { |row| row["paid_usd"].to_d }.round(2)
      pending_usd = lines.sum { |row| row["pending_usd"].to_d }.round(2)
      overall_status = if pending_usd <= 0.01.to_d
          "paid"
        elsif paid_usd.positive?
          "partial"
        else
          "pending"
        end

      details = debt.service_cost_details_hash.deep_dup
      details["version"] ||= 1
      details["service_id"] ||= debt.service_id
      details["service_name"] ||= debt.service&.description.to_s
      details["total_usd"] = lines.sum { |row| row["amount_usd"].to_d }.round(2).to_f
      details["paid_usd"] = paid_usd.to_f
      details["pending_usd"] = pending_usd.to_f
      details["status"] = overall_status
      details["lines"] = lines

      debt.update!(
        service_cost_details: details,
        service_cost_pending: pending_usd.positive?,
      )

      sync_paid_service_cost_snapshot_to_sale!(debt: debt, details: details) if pending_usd <= 0.01.to_d
    end

    redirect_to pending_cost_redirect_path(debt: debt),
                notice: "Pago registrado en la linea de costo seleccionada."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to pending_cost_redirect_path(debt: debt),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def new
    @service = current_business.services.new(pricing_mode: :fixed, currency_base_price: "Dolar BCV")
  end

  def create
    @service = current_business.services.new(service_params)

    if @service.save
      redirect_to services_path, notice: "Servicio creado exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    unless @service.show_allowed_for?(Current.user)
      return render_show_blocked(
               @service.restricted_service? ? "Este servicio esta restringido y solo puede verlo el administrador." : "Este servicio no esta disponible en este momento."
             )
    end

    respond_to do |format|
      format.html { render partial: "services/show", locals: { service: @service } }
    end
  end

  def edit
    @service.service_expense_structures.build if @service.cost && @service.service_expense_structures.empty?
  end

  def update
    updated = false

    Service.transaction do
      updated = @service.update(service_params)
      raise ActiveRecord::Rollback unless updated

      references_synced = sync_expense_reference_from_raw_params!(
        service: @service,
        raw_service: params[:service],
      )

      unless references_synced
        updated = false
        raise ActiveRecord::Rollback
      end
    end

    if updated
      redirect_to services_path, notice: "Servicio actualizado exitosamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @service.destroy
      redirect_to services_path, notice: "Service deleted successfully."
    else
      redirect_to services_path, alert: "Failed to delete the service."
    end
  end

  private

  def set_service
    @service = current_business
      .services
      .includes(:system_service, service_expense_structures: %i[
                                   service_variable_expenses
                                 ] + [
                                   { service_manager_expenses: :manager },
                                   { service_nested_expenses: :nested_service },
                                   { service_product_expenses: [:product_variation, { producto: :product_variations }] },
                                 ])
      .find(params[:id])
  end

  def set_form_collections
    @managers = Manager.order(:name)
    @products_for_expenses = if current_business.present?
        current_business.productos.includes(:product_variations).order(:descripcion)
      else
        Producto.none
      end

    scope = current_business.services.includes(:system_service).where(nested_available: true).order(:description)
    @nested_services_for_expenses = @service&.id.present? ? scope.where.not(id: @service.id) : scope

    rate = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : 0.to_d
    @service_expenses_bcv_rate = rate.positive? ? rate : TasaCambio.latest_value("Dolar BCV").to_d

    latest_rates = TasaCambio.latest_by_description
    @expense_currency_rows = build_currency_rows(latest_rates: latest_rates, include_unidad_vi: false)
    @service_price_currency_rows = build_currency_rows(latest_rates: latest_rates, include_unidad_vi: true)
  end

  def service_params
    raw_service = params.require(:service)

    permitted = raw_service.permit(
      :description,
      :pricing_mode,
      :sale_price,
      :currency_base_price,
      :value_units,
      :cost,
      :nested_available,
      :caution_service,
      :restricted_service,
      :auto_cost_stock_discount,
      :system_service_id,
      :physical_requirements,
      :digital_requirements,
      :required_data,
      :personal_steps,
      :note,
      :delivery_content,
      :delivery_time,
      :available,
      service_managers_attributes: %i[id manager_id cost reference_cost _destroy],
      service_expense_structures_attributes: [
        :id,
        :description,
        :active_for_sales,
        :_destroy,
        { service_manager_expenses_attributes: %i[id manager_id currency_reference amount_reference amount_usd
                                                 amount_bs _destroy] },
        { service_variable_expenses_attributes: %i[id description currency_reference amount_reference amount_usd
                                                  amount_bs _destroy] },
        { service_nested_expenses_attributes: %i[id nested_service_id quantity currency_reference amount_reference
                                                _destroy] },
        { service_product_expenses_attributes: %i[id producto_id product_variation_id quantity _destroy] },
      ],
    )

    merge_expense_reference_fields!(permitted: permitted, raw_service: raw_service)

    unless ActiveModel::Type::Boolean.new.cast(permitted[:cost])
      permitted.delete(:service_expense_structures_attributes)
    end

    permitted
  end

  def merge_expense_reference_fields!(permitted:, raw_service:)
    permitted_structures = permitted[:service_expense_structures_attributes]
    raw_structures = raw_service[:service_expense_structures_attributes]

    return unless permitted_structures.respond_to?(:each)
    return unless raw_structures.respond_to?(:[])

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_manager_expenses_attributes,
    )

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_variable_expenses_attributes,
    )

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_nested_expenses_attributes,
    )
  end

  def merge_nested_reference_fields!(permitted_structures:, raw_structures:, nested_key:)
    permitted_structures.each do |structure_key, permitted_structure|
      next unless permitted_structure.respond_to?(:[])

      raw_structure = raw_structures[structure_key.to_s] || raw_structures[structure_key.to_sym]
      next unless raw_structure.respond_to?(:[])

      raw_nested = raw_structure[nested_key] || raw_structure[nested_key.to_s]
      next unless raw_nested.respond_to?(:each)

      permitted_nested = permitted_structure[nested_key] || permitted_structure[nested_key.to_s]
      permitted_nested ||= ActionController::Parameters.new

      raw_nested.each do |row_key, raw_row|
        next unless raw_row.respond_to?(:[])

        currency_reference = raw_row[:currency_reference] || raw_row["currency_reference"]
        amount_reference = raw_row[:amount_reference] || raw_row["amount_reference"]
        next if currency_reference.blank? && amount_reference.blank?

        permitted_row = permitted_nested[row_key] || permitted_nested[row_key.to_s]
        permitted_row ||= ActionController::Parameters.new

        permitted_row[:currency_reference] = currency_reference if currency_reference.present?
        permitted_row[:amount_reference] = amount_reference if amount_reference.present?

        permitted_nested[row_key] = permitted_row
      end

      permitted_structure[nested_key] = permitted_nested
    end
  end

  def sync_expense_reference_from_raw_params!(service:, raw_service:)
    raw_structures = raw_service&.[](:service_expense_structures_attributes) ||
                     raw_service&.[]("service_expense_structures_attributes")

    return true unless raw_structures.respond_to?(:each)

    success = true

    raw_structures.each do |_structure_key, raw_structure|
      next unless raw_structure.respond_to?(:[])

      structure_id = raw_structure[:id] || raw_structure["id"]
      next if structure_id.blank?

      structure = service.service_expense_structures.find_by(id: structure_id)
      next unless structure

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_manager_expenses,
        raw_rows: raw_structure[:service_manager_expenses_attributes] || raw_structure["service_manager_expenses_attributes"],
      )

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_variable_expenses,
        raw_rows: raw_structure[:service_variable_expenses_attributes] || raw_structure["service_variable_expenses_attributes"],
      )

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_nested_expenses,
        raw_rows: raw_structure[:service_nested_expenses_attributes] || raw_structure["service_nested_expenses_attributes"],
      )
    end

    success
  end

  def sync_nested_expense_reference_rows!(scope:, raw_rows:)
    return true unless raw_rows.respond_to?(:each)

    success = true

    raw_rows.each do |_row_key, raw_row|
      next unless raw_row.respond_to?(:[])

      destroy_flag = ActiveModel::Type::Boolean.new.cast(raw_row[:_destroy] || raw_row["_destroy"])
      next if destroy_flag

      row_id = raw_row[:id] || raw_row["id"]
      next if row_id.blank?

      record = scope.find_by(id: row_id)
      next unless record

      attrs = {}
      currency_reference = raw_row[:currency_reference] || raw_row["currency_reference"]
      amount_reference = raw_row[:amount_reference] || raw_row["amount_reference"]

      attrs[:currency_reference] = currency_reference if currency_reference.present?
      attrs[:amount_reference] = amount_reference if amount_reference.present?
      next if attrs.empty?

      record.assign_attributes(attrs)
      next unless record.changed?

      next if record.save

      success = false
      record.errors.full_messages.each do |message|
        @service.errors.add(:base, message)
      end
    end

    success
  end

  def set_pending_cost_accounts
    @pending_cost_accounts = current_business.accounts.where(active: true).order(:currency, :name)
  end

  def pending_cost_filters_from_params
    {
      query_text: params[:query_text].to_s.strip,
      fecha_desde: parse_pending_cost_filter_date(params[:fecha_desde]),
      fecha_hasta: parse_pending_cost_filter_date(params[:fecha_hasta]),
      automatico: normalize_pending_cost_automatic_mode(params[:automatico]),
      system_service_id: parse_pending_cost_filter_integer(params[:system_service_id]),
      manager_id: parse_pending_cost_filter_integer(params[:manager_id]),
    }
  end

  def parse_pending_cost_filter_integer(value)
    parsed = value.to_i
    parsed.positive? ? parsed : nil
  end

  def normalize_pending_cost_automatic_mode(value)
    normalized = value.to_s.strip
    return normalized if %w[all automaticos no_automaticos].include?(normalized)

    "all"
  end

  def parse_pending_cost_filter_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    return Date.strptime(raw, "%d-%m-%Y") if raw.match?(/\A\d{2}-\d{2}-\d{4}\z/)

    Date.iso8601(raw)
  rescue ArgumentError
    nil
  end

  def apply_pending_cost_sales_date_filters(scope:, filters:)
    filtered_scope = scope

    if filters[:fecha_desde].present?
      filtered_scope = filtered_scope.where("DATE(ventas.created_at) >= ?", filters[:fecha_desde])
    end

    if filters[:fecha_hasta].present?
      filtered_scope = filtered_scope.where("DATE(ventas.created_at) <= ?", filters[:fecha_hasta])
    end

    filtered_scope
  end

  def build_pending_cost_sold_service_rows_for_sales(sales:)
    sold_service_items = sales.flat_map do |sale|
      sale.venta_items.select { |item| item.producto_id.blank? }
    end
    service_lookup = build_pending_cost_service_lookup(service_items: sold_service_items)
    services_by_id = service_lookup[:services_by_id]

    settlements_by_sale_id = {}
    nested_source_ids = []

    sales.each do |sale|
      settlements = pending_cost_settlements_for_sale(sale: sale)
      settlements_by_sale_id[sale.id] = settlements

      settlements.each do |settlement|
        Array(settlement["detail_lines"]).each do |raw_line|
          line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}
          next unless line["classification"].to_s == "nested_expense"
          next unless line["source_type"].to_s == "ServiceNestedExpense"

          source_id = line["source_id"].to_i
          nested_source_ids << source_id if source_id.positive?
        end
      end
    end

    nested_expense_lookup = ServiceNestedExpense
      .includes(nested_service: :system_service)
      .where(id: nested_source_ids.uniq)
      .index_by(&:id)

    rows = []

    sales.each do |sale|
      sale_settlements = settlements_by_sale_id[sale.id] || []
      settlement_queue_by_name = Hash.new { |hash, key| hash[key] = [] }
      sale_settlements.each do |settlement|
        key = normalized_pending_cost_lookup_value(settlement["service_name"])
        next if key.blank?

        settlement_queue_by_name[key] << settlement
      end

      sale_payable_debts = sale.service_cost_debts.select(&:payable?)
      debts_by_service_id = sale_payable_debts.group_by(&:service_id)
      debts_by_service_name = sale_payable_debts.group_by do |debt|
        normalized_pending_cost_lookup_value(
          debt.service_cost_details_hash["service_name"].presence || debt.service&.description,
        )
      end

      service_item_groups = sale
        .venta_items
        .select { |item| item.producto_id.blank? }
        .group_by do |item|
        [
          normalized_pending_cost_lookup_value(item.product_name),
          normalized_pending_cost_lookup_value(item.variation_name),
        ]
      end

      service_item_groups.each do |(name_key, _system_key), grouped_items|
        next if grouped_items.blank?

        first_item = grouped_items.first
        service_name_snapshot = first_item.product_name.to_s.strip.presence || "Servicio"
        system_name_snapshot = first_item.variation_name.to_s.strip
        quantity = grouped_items.sum { |item| item.quantity.to_d }.round(2)
        quantity = 1.to_d unless quantity.positive?
        subtotal_usd = grouped_items.sum { |item| item.subtotal_usd.to_d }.round(2)
        unit_price_usd = (subtotal_usd / quantity).round(2)

        settlement = settlement_queue_by_name[name_key].shift

        resolved_service = resolve_pending_cost_service_for_snapshot(
          service_name: service_name_snapshot,
          system_name: system_name_snapshot,
          lookup: service_lookup,
        )
        settlement_service_id = settlement.is_a?(Hash) ? settlement["service_id"].to_i : 0
        if resolved_service.blank? && settlement_service_id.positive?
          resolved_service = services_by_id[settlement_service_id]
        end

        debt = if resolved_service&.id.present?
            debts_by_service_id[resolved_service.id]&.max_by(&:id)
          end
        debt ||= debts_by_service_name[name_key]&.max_by(&:id)

        status_payload = pending_cost_status_for_direct_row(
          service: resolved_service,
          settlement: settlement,
          debt: debt,
        )

        rows << {
          sale_id: sale.id,
          sold_at: sale.created_at,
          nested_sale: false,
          parent_service_name: nil,
          service_id: resolved_service&.id,
          service_name: resolved_service&.description.to_s.strip.presence || service_name_snapshot,
          service_system_name: resolved_service&.system_service&.name.to_s.strip.presence || system_name_snapshot,
          system_service_id: resolved_service&.system_service_id,
          quantity: quantity,
          sale_unit_price_usd: unit_price_usd,
          sale_total_usd: subtotal_usd,
          agreed_price_usd: resolved_service&.to_agree? ? unit_price_usd : nil,
          automatic_cost: resolved_service&.auto_cost_stock_discount? || false,
          has_cost_structure: service_has_active_cost_structure?(resolved_service),
          cost_status: status_payload[:status],
          cost_status_label: status_payload[:label],
          cost_status_class: status_payload[:css_class],
          pending_cost_usd: status_payload[:pending_usd],
          detail_debt_id: debt&.id,
          search_text: [
            service_name_snapshot,
            resolved_service&.description,
            system_name_snapshot,
            sale.id,
          ].join(" ").downcase,
        }
      end

      sale_settlements.each do |settlement|
        parent_service_name = settlement["service_name"].to_s.strip
        parent_name_key = normalized_pending_cost_lookup_value(parent_service_name)
        parent_service = services_by_id[settlement["service_id"].to_i]
        if parent_service.blank?
          parent_service = resolve_pending_cost_service_for_snapshot(
            service_name: parent_service_name,
            system_name: nil,
            lookup: service_lookup,
          )
        end

        parent_debt = if parent_service&.id.present?
            debts_by_service_id[parent_service.id]&.max_by(&:id)
          end
        parent_debt ||= debts_by_service_name[parent_name_key]&.max_by(&:id)

        debt_lines_by_id = if parent_debt.present?
            normalized_pending_cost_lines_for(parent_debt).index_by { |line| line["line_id"].to_s }
          else
            {}
          end

        Array(settlement["detail_lines"]).each do |raw_line|
          line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}
          next unless line["classification"].to_s == "nested_expense"

          line_total_usd = line["amount_usd"].to_d.round(2)
          next unless line_total_usd.positive?

          line_quantity = line["quantity"].to_d.round(2)
          line_quantity = 1.to_d unless line_quantity.positive?
          line_unit_usd = (line_total_usd / line_quantity).round(2)

          nested_service = nil
          if line["source_type"].to_s == "ServiceNestedExpense"
            source_id = line["source_id"].to_i
            nested_service = nested_expense_lookup[source_id]&.nested_service if source_id.positive?
          end

          nested_service_name = nested_service&.description.to_s.strip.presence ||
                                line["source_name"].to_s.strip.presence ||
                                "Servicio anidado"
          debt_line = debt_lines_by_id[line["line_id"].to_s]

          status_payload = pending_cost_status_for_nested_row(
            service: nested_service,
            settlement: settlement,
            debt_line: debt_line,
            line_amount_usd: line_total_usd,
          )

          rows << {
            sale_id: sale.id,
            sold_at: sale.created_at,
            nested_sale: true,
            parent_service_name: parent_service_name,
            service_id: nested_service&.id,
            service_name: nested_service_name,
            service_system_name: nested_service&.system_service&.name.to_s.strip,
            system_service_id: nested_service&.system_service_id,
            quantity: line_quantity,
            sale_unit_price_usd: line_unit_usd,
            sale_total_usd: line_total_usd,
            agreed_price_usd: nested_service&.to_agree? ? line_unit_usd : nil,
            automatic_cost: nested_service&.auto_cost_stock_discount? || false,
            has_cost_structure: service_has_active_cost_structure?(nested_service),
            cost_status: status_payload[:status],
            cost_status_label: status_payload[:label],
            cost_status_class: status_payload[:css_class],
            pending_cost_usd: status_payload[:pending_usd],
            detail_debt_id: parent_debt&.id,
            search_text: [
              nested_service_name,
              parent_service_name,
              nested_service&.system_service&.name,
              sale.id,
            ].join(" ").downcase,
          }
        end
      end
    end

    rows
  end

  def pending_cost_settlements_for_sale(sale:)
    parsed_notes = begin
        parsed = JSON.parse(sale.notes.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

    Array(parsed_notes["service_cost_settlements"]).filter_map do |row|
      next unless row.is_a?(Hash)

      row.deep_stringify_keys
    end
  end

  def build_pending_cost_service_lookup(service_items:)
    descriptions = service_items.filter_map { |item| item.product_name.to_s.strip.presence }.uniq

    by_key = Hash.new { |hash, key| hash[key] = [] }
    by_description = Hash.new { |hash, key| hash[key] = [] }
    return { by_key: by_key, by_description: by_description, services_by_id: {} } if descriptions.empty?

    services = current_business
      .services
      .includes(:system_service, :service_expense_structures)
      .where(description: descriptions)
      .to_a

    services.each do |service|
      description_key = normalized_pending_cost_lookup_value(service.description)
      next if description_key.blank?

      system_key = normalized_pending_cost_lookup_value(service.system_service&.name)
      by_key[[description_key, system_key]] << service
      by_description[description_key] << service
    end

    {
      by_key: by_key,
      by_description: by_description,
      services_by_id: services.index_by(&:id),
    }
  end

  def resolve_pending_cost_service_for_snapshot(service_name:, system_name:, lookup:)
    description_key = normalized_pending_cost_lookup_value(service_name)
    return nil if description_key.blank?

    system_key = normalized_pending_cost_lookup_value(system_name)
    exact_matches = lookup[:by_key][[description_key, system_key]]
    return exact_matches.first if exact_matches.present?

    fallback_matches = lookup[:by_description][description_key]
    return fallback_matches.first if fallback_matches.size == 1

    nil
  end

  def normalized_pending_cost_lookup_value(value)
    value.to_s.strip.downcase.presence
  end

  def service_has_active_cost_structure?(service)
    return false if service.blank?

    service.service_expense_structures.any? { |structure| ActiveModel::Type::Boolean.new.cast(structure.active_for_sales) }
  end

  def pending_cost_status_for_direct_row(service:, settlement:, debt:)
    if debt.present?
      return pending_cost_status_metadata(
               debt.service_cost_overall_status,
               pending_usd: debt.service_cost_pending_total_usd,
               total_usd: debt.service_cost_total_usd,
             )
    end

    settlement_hash = settlement.is_a?(Hash) ? settlement.deep_stringify_keys : {}
    if settlement_hash.present?
      pending_usd = settlement_hash["pending_cost_usd"].to_d.round(2)
      paid_usd = settlement_hash["paid_cost_usd"].to_d.round(2)
      total_usd = settlement_hash["total_cost_usd"].to_d.round(2)

      status = if pending_usd <= 0.01.to_d
          "paid"
        elsif paid_usd.positive?
          "partial"
        else
          "pending"
        end

      return pending_cost_status_metadata(status, pending_usd: pending_usd, total_usd: total_usd)
    end

    pending_cost_status_metadata("no_cost", pending_usd: 0.to_d, total_usd: 0.to_d)
  end

  def pending_cost_status_for_nested_row(service:, settlement:, debt_line:, line_amount_usd:)
    if debt_line.present?
      return pending_cost_status_metadata(
               debt_line["status"],
               pending_usd: debt_line["pending_usd"].to_d,
               total_usd: debt_line["amount_usd"].to_d,
             )
    end

    settlement_hash = settlement.is_a?(Hash) ? settlement.deep_stringify_keys : {}
    return pending_cost_status_metadata("no_cost", pending_usd: 0.to_d, total_usd: line_amount_usd) if settlement_hash.blank?

    pending_usd = settlement_hash["pending_cost_usd"].to_d.round(2)
    paid_usd = settlement_hash["paid_cost_usd"].to_d.round(2)

    status = if pending_usd <= 0.01.to_d
        "paid"
      elsif paid_usd.positive?
        "partial"
      else
        "pending"
      end

    approximated_pending_usd = status == "paid" ? 0.to_d : line_amount_usd.to_d
    pending_cost_status_metadata(status, pending_usd: approximated_pending_usd, total_usd: line_amount_usd)
  end

  def pending_cost_status_metadata(status, pending_usd:, total_usd:)
    normalized = status.to_s
    normalized = "pending" unless %w[pending partial paid no_cost].include?(normalized)

    label = case normalized
      when "pending"
        "Debe"
      when "partial"
        "Parcial"
      when "paid"
        "Pagado"
      else
        "Sin costo"
      end

    css_class = case normalized
      when "pending"
        "bg-rose-100 text-rose-700 ring-rose-200"
      when "partial"
        "bg-amber-100 text-amber-700 ring-amber-200"
      when "paid"
        "bg-emerald-100 text-emerald-700 ring-emerald-200"
      else
        "bg-slate-100 text-slate-600 ring-slate-200"
      end

    {
      status: normalized,
      label: label,
      css_class: css_class,
      pending_usd: pending_usd.to_d.round(2),
      total_usd: total_usd.to_d.round(2),
    }
  end

  def filter_pending_cost_sold_rows(rows:, filters:)
    filtered_rows = rows

    if filters[:query_text].present?
      query = filters[:query_text].downcase
      filtered_rows = filtered_rows.select { |row| row[:search_text].to_s.include?(query) }
    end

    case filters[:automatico]
    when "automaticos"
      filtered_rows = filtered_rows.select { |row| row[:automatic_cost] }
    when "no_automaticos"
      filtered_rows = filtered_rows.reject { |row| row[:automatic_cost] }
    end

    if filters[:system_service_id].present?
      filtered_rows = filtered_rows.select do |row|
        row[:system_service_id].to_i == filters[:system_service_id].to_i
      end
    end

    if filters[:manager_id].present?
      service_ids_for_manager = manager_service_ids_for_pending_cost_filter(manager_id: filters[:manager_id])
      filtered_rows = filtered_rows.select do |row|
        service_ids_for_manager.include?(row[:service_id].to_i)
      end
    end

    filtered_rows
  end

  def manager_service_ids_for_pending_cost_filter(manager_id:)
    return [] if manager_id.blank?

    ServiceManagerExpense
      .joins(:service_expense_structure)
      .where(manager_id: manager_id, service_expense_structures: { service_id: current_business.services.select(:id) })
      .distinct
      .pluck("service_expense_structures.service_id")
      .map(&:to_i)
  end

  def paginate_pending_cost_sold_rows(rows:)
    return [] if rows.blank?

    items_per_page = 20
    total_rows = rows.size
    total_pages = (total_rows / items_per_page.to_f).ceil
    requested_page = params[:page].to_i
    requested_page = 1 if requested_page <= 0
    requested_page = total_pages if requested_page > total_pages && total_pages.positive?

    @pagy = Pagy.new(count: total_rows, page: requested_page, items: items_per_page)
    rows[@pagy.offset, @pagy.items] || []
  end

  def normalized_pending_cost_lines_for(debt)
    lines = debt.service_cost_lines

    if lines.empty?
      total_usd = debt.amount.to_d.round(2)
      paid_usd = debt.paid_amount.to_d.round(2)
      paid_usd = total_usd if paid_usd > total_usd
      pending_usd = (total_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      lines = [
        {
          "line_id" => "debt-#{debt.id}-general",
          "structure_description" => "Estructura general",
          "classification" => "general",
          "classification_label" => "Costo general",
          "source_name" => debt.service&.description.to_s.presence || debt.display_name,
          "amount_usd" => total_usd.to_f,
          "paid_usd" => paid_usd.to_f,
          "pending_usd" => pending_usd.to_f,
          "status" => if pending_usd <= 0
            "paid"
          else
            (paid_usd.positive? ? "partial" : "pending")
          end,
          "source_updatable" => false,
        },
      ]
    end

    lines.map do |raw_line|
      line = raw_line.deep_stringify_keys
      line["classification_label"] =
        line["classification_label"].to_s.presence || pending_cost_classification_label(line["classification"])
      line["structure_description"] = line["structure_description"].to_s.presence || "Sin estructura"
      line["source_name"] = line["source_name"].to_s.presence || "Sin detalle"
      line["source_updatable"] = ActiveModel::Type::Boolean.new.cast(line["source_updatable"])
      hydrate_pending_cost_display_amounts!(line: line, debt: debt)
      line
    end
  end

  def hydrate_pending_cost_display_amounts!(line:, debt:)
    snapshot = resolve_source_reference_snapshot(line)
    reference = snapshot[:reference].to_s.strip
    return if reference.blank?

    amount_usd = line["amount_usd"].to_d.round(2)
    paid_usd = line["paid_usd"].to_d.round(2)
    pending_usd = line["pending_usd"].to_d.round(2)

    configured_total_reference = snapshot[:amount_reference_total].to_d.round(2)
    total_reference = if configured_total_reference.positive?
        configured_total_reference
      else
        convert_usd_to_reference_amount(
          amount_usd: amount_usd,
          reference: reference,
          on_date: debt&.issued_on,
        ).to_d.round(2)
      end

    paid_reference = convert_usd_to_reference_amount(
      amount_usd: paid_usd,
      reference: reference,
      on_date: debt&.issued_on,
    ).to_d.round(2)
    pending_reference = convert_usd_to_reference_amount(
      amount_usd: pending_usd,
      reference: reference,
      on_date: debt&.issued_on,
    ).to_d.round(2)

    line["source_currency_reference"] = reference
    line["display_currency_reference"] = reference
    line["display_currency_symbol"] = pending_cost_reference_symbol(reference)
    line["display_amount_reference_unit"] = snapshot[:amount_reference_unit].to_d.round(2).to_f
    line["display_amount_reference_total"] = total_reference.to_f
    line["display_paid_reference_total"] = paid_reference.to_f
    line["display_pending_reference_total"] = pending_reference.to_f
  end

  def resolve_source_reference_snapshot(line)
    line_hash = line.deep_stringify_keys
    reference = line_hash["source_currency_reference"].to_s.strip
    quantity = line_hash["quantity"].to_d
    quantity = 1.to_d unless quantity.positive?

    unit_reference = line_hash["source_amount_reference_unit"].to_d.round(2)
    total_reference = line_hash["source_amount_reference_total"].to_d.round(2)

    if total_reference.positive? || unit_reference.positive?
      total_reference = (unit_reference * quantity).round(2) if total_reference <= 0 && unit_reference.positive?

      return {
               reference: reference,
               amount_reference_unit: unit_reference,
               amount_reference_total: total_reference,
             }
    end

    source_type = line_hash["source_type"].to_s
    source_id = line_hash["source_id"]

    source_class = {
      "ServiceManagerExpense" => ServiceManagerExpense,
      "ServiceVariableExpense" => ServiceVariableExpense,
      "ServiceNestedExpense" => ServiceNestedExpense,
    }[source_type]

    if source_class.blank? || source_id.blank?
      return { reference: reference, amount_reference_unit: 0.to_d,
               amount_reference_total: 0.to_d }
    end

    source_row = source_class.find_by(id: source_id)
    return { reference: reference, amount_reference_unit: 0.to_d, amount_reference_total: 0.to_d } if source_row.blank?

    source_reference = if source_row.respond_to?(:currency_reference)
        source_row.currency_reference.to_s.strip
      else
        reference
      end
    source_reference = reference if source_reference.blank?

    source_unit_reference = if source_row.respond_to?(:amount_reference)
        source_row.amount_reference.to_d.round(2)
      else
        0.to_d
      end
    source_total_reference = source_unit_reference.positive? ? (source_unit_reference * quantity).round(2) : 0.to_d

    {
      reference: source_reference,
      amount_reference_unit: source_unit_reference,
      amount_reference_total: source_total_reference,
    }
  end

  def pending_cost_reference_symbol(reference)
    normalized = reference.to_s.strip
    return "Bs" if normalized == "Bs"
    return "$" if %w[Dolar BCV USD $].include?(normalized)

    TasaCambio.latest_for(normalized)&.symbol.to_s.presence || normalized
  end

  def pending_cost_expected_account_currency_for(line:, debt_currency:)
    reference = line["source_currency_reference"].to_s.strip
    reference = line["display_currency_reference"].to_s.strip if reference.blank?

    reference_currency = pending_cost_reference_currency(reference)
    return "USDT" if reference_currency == "USDT"
    return "VES" if %w[VES USD EUR].include?(reference_currency)

    normalized_debt_currency = debt_currency.to_s.strip.upcase
    return normalized_debt_currency if normalized_debt_currency.present?

    nil
  end

  def pending_cost_expected_account_currency_label(currency)
    case currency.to_s.upcase
    when "VES"
      "Bs"
    when "USDT"
      "USDT"
    else
      currency.to_s.upcase
    end
  end

  def build_pending_cost_currency_rates(rows:, accounts:)
    candidate_currencies = []

    Array(rows).each do |row|
      candidate_currencies << row[:debt_currency]
      Array(row[:lines]).each do |line|
        candidate_currencies << line["debt_currency"]
      end
    end

    Array(accounts).each do |account|
      candidate_currencies << account.currency
    end

    normalized = candidate_currencies
      .map { |value| value.to_s.strip.upcase }
      .select(&:present?)
      .uniq

    rates = { "VES" => 1.0 }

    normalized.each do |currency|
      next if rates.key?(currency)

      rates[currency] = CurrencyConverter.rate_to_ves(currency, on_date: Date.current).to_d.to_f
    end

    rates
  end

  def pending_cost_redirect_path(debt:)
    return pending_costs_services_path unless params[:redirect_to_detail].to_s == "1"
    return pending_costs_services_path if debt.blank?

    pending_cost_detail_services_path(debt_id: debt.id)
  end

  def pending_cost_status_from_lines(lines)
    pending_usd = Array(lines).sum { |line| line["pending_usd"].to_d }.round(2)
    paid_usd = Array(lines).sum { |line| line["paid_usd"].to_d }.round(2)

    return "paid" if pending_usd <= 0.01.to_d
    return "partial" if paid_usd.positive?

    "pending"
  end

  def pending_cost_classification_label(classification)
    case classification.to_s
    when "manager_expense"
      "Gestor"
    when "variable_expense"
      "Gasto variable"
    when "nested_expense"
      "Servicio anidado"
    when "product_expense"
      "Consumible"
    when "adjustment"
      "Ajuste"
    else
      "Costo general"
    end
  end

  def parse_pending_cost_decimal(value)
    return 0.to_d if value.blank?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip
                   .gsub(/\s/, "")
                   .gsub(/[^\d.,-]/, "")

    normalized = if cleaned.include?(",")
        cleaned.gsub(".", "").gsub(",", ".")
      else
        cleaned
      end

    BigDecimal(normalized)
  rescue ArgumentError
    0.to_d
  end

  def parse_pending_cost_payment_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    return Date.strptime(raw, "%d-%m-%Y") if raw.match?(/\A\d{2}-\d{2}-\d{4}\z/)

    Date.iso8601(raw)
  rescue ArgumentError
    nil
  end

  def lock_paid_pending_cost_line_snapshot!(line:, paid_amount_original:, paid_currency:, on_date:)
    return unless line["status"].to_s == "paid"

    snapshot = resolve_source_reference_snapshot(line)
    reference = snapshot[:reference].to_s.strip
    return if reference.blank?

    quantity = line["quantity"].to_d
    quantity = 1.to_d unless quantity.positive?

    unit_reference = line["source_amount_reference_unit"].to_d.round(2)
    total_reference = line["source_amount_reference_total"].to_d.round(2)

    if total_reference <= 0 || unit_reference <= 0
      total_reference = convert_paid_amount_to_reference_amount(
        amount: paid_amount_original,
        from_currency: paid_currency,
        reference: reference,
        on_date: on_date,
      )

      if total_reference <= 0
        total_reference = convert_usd_to_reference_amount(
          amount_usd: line["amount_usd"].to_d,
          reference: reference,
          on_date: on_date,
        )
      end

      if total_reference.positive?
        total_reference = total_reference.round(2)
        unit_reference = (total_reference / quantity).round(2)
      end
    end

    line["source_currency_reference"] = reference
    line["source_amount_reference_unit"] = unit_reference.to_f if unit_reference.positive?
    line["source_amount_reference_total"] = total_reference.to_f if total_reference.positive?
  end

  def sync_paid_service_cost_snapshot_to_sale!(debt:, details:)
    sale = debt.venta
    return if sale.blank?

    notes_payload = parse_pending_cost_sale_notes(sale.notes)
    settlements = Array(notes_payload["service_cost_settlements"]).filter_map do |row|
      next unless row.is_a?(Hash)

      row.deep_stringify_keys
    end

    normalized_lines = normalize_pending_cost_lines_for_sale_notes(details["lines"])
    total_usd = details["total_usd"].to_d.round(2)
    paid_usd = details["paid_usd"].to_d.round(2)
    pending_usd = details["pending_usd"].to_d.round(2)

    service_id = details["service_id"].to_i
    service_id = debt.service_id.to_i if service_id <= 0 && debt.service_id.present?

    service_name = details["service_name"].to_s.strip
    service_name = debt.service&.description.to_s.strip if service_name.blank?
    service_name = debt.display_name.to_s.strip if service_name.blank?

    settlement = if service_id.positive?
        settlements.find { |row| row["service_id"].to_i == service_id }
      end
    settlement ||= settlements.find do |row|
      row["service_name"].to_s.strip.casecmp?(service_name)
    end

    quantity = settlement&.dig("quantity").to_d
    if quantity <= 0
      quantity = normalized_lines.sum { |line| line["quantity"].to_d }.round(2)
      quantity = 1.to_d unless quantity.positive?
    end

    snapshot = {
      "service_name" => service_name,
      "quantity" => quantity.to_f,
      "unit_cost_usd" => (total_usd / quantity).round(2).to_f,
      "total_cost_usd" => total_usd.to_f,
      "paid_cost_usd" => paid_usd.to_f,
      "pending_cost_usd" => pending_usd.to_f,
      "detail_lines" => normalized_lines,
    }
    snapshot["service_id"] = service_id if service_id.positive?

    if settlement.present?
      settlement.merge!(snapshot)
    else
      settlements << snapshot
    end

    notes_payload["service_cost_settlements"] = settlements
    sale.update_columns(notes: notes_payload.to_json, updated_at: Time.current)
  end

  def parse_pending_cost_sale_notes(raw_notes)
    parsed = JSON.parse(raw_notes.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def normalize_pending_cost_lines_for_sale_notes(lines)
    Array(lines).filter_map do |raw_line|
      next unless raw_line.is_a?(Hash)

      line = raw_line.deep_stringify_keys
      amount_usd = line["amount_usd"].to_d.round(2)
      paid_usd = line["paid_usd"].to_d.round(2)
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
        "amount_usd" => amount_usd.to_f,
        "paid_usd" => paid_usd.to_f,
        "pending_usd" => pending_usd.to_f,
        "status" => status,
      )
    end
  end

  def apply_pending_cost_source_snapshot!(line:, snapshot:, debt:)
    return if snapshot.blank?

    line["source_currency_reference"] = snapshot[:reference].to_s
    line["source_amount_reference_unit"] = snapshot[:amount_reference_unit].to_d.round(2).to_f
    line["source_amount_reference_total"] = snapshot[:amount_reference_total].to_d.round(2).to_f

    hydrate_pending_cost_display_amounts!(line: line, debt: debt)
  end

  def update_pending_cost_source_row!(line:, amount_usd:, paid_amount_original:, paid_currency:, on_date:)
    return unless ActiveModel::Type::Boolean.new.cast(line["source_updatable"])

    source_type = line["source_type"].to_s
    source_id = line["source_id"]
    return if source_id.blank?

    source_class = {
      "ServiceManagerExpense" => ServiceManagerExpense,
      "ServiceVariableExpense" => ServiceVariableExpense,
    }[source_type]
    return unless source_class

    source_row = source_class.find_by(id: source_id)
    return unless source_row

    reference = line["source_currency_reference"].to_s.strip.presence || source_row.currency_reference.to_s
    reference = "Dolar BCV" if reference.blank?

    reference_amount = convert_paid_amount_to_reference_amount(
      amount: paid_amount_original,
      from_currency: paid_currency,
      reference: reference,
      on_date: on_date,
    )

    if reference_amount.to_d <= 0
      reference_amount = convert_usd_to_reference_amount(
        amount_usd: amount_usd,
        reference: reference,
        on_date: on_date,
      )
    end

    return unless reference_amount.to_d.positive?

    source_row.update!(
      currency_reference: reference,
      amount_reference: reference_amount.to_d.round(2),
    )

    {
      reference: source_row.currency_reference.to_s.strip.presence || reference,
      amount_reference_unit: source_row.amount_reference.to_d.round(2),
      amount_reference_total: source_row.amount_reference.to_d.round(2),
    }
  end

  def convert_paid_amount_to_reference_amount(amount:, from_currency:, reference:, on_date:)
    paid_amount = amount.to_d
    return 0.to_d unless paid_amount.positive?

    target_currency = pending_cost_reference_currency(reference)
    return 0.to_d if target_currency.blank?

    source_currency = from_currency.to_s.strip.upcase
    return paid_amount.round(2) if source_currency == target_currency

    conversion = CurrencyConverter.convert(
      amount: paid_amount,
      from_currency: source_currency,
      to_currency: target_currency,
      on_date: on_date,
    )

    conversion&.dig(:amount).to_d.round(2)
  end

  def pending_cost_reference_currency(reference)
    normalized = reference.to_s.strip.upcase
    return "" if normalized.blank?

    return "USDT" if normalized.include?("USDT")
    return "VES" if ["BS", "VES", "BOLIVAR", "BOLIVARES"].include?(normalized)
    return "USD" if normalized == "$" || normalized.include?("DOLAR") || normalized.include?("USD")
    return "EUR" if normalized == "€" || normalized.include?("EURO") || normalized.include?("EUR")
    return normalized if Account::CURRENCIES.key?(normalized)

    ""
  end

  def convert_usd_to_reference_amount(amount_usd:, reference:, on_date:)
    usd_value = amount_usd.to_d
    return 0.to_d unless usd_value.positive?

    normalized_reference = reference.to_s.strip
    return usd_value.round(2) if normalized_reference.blank? || %w[Dolar BCV $ USD].include?(normalized_reference)

    usd_to_bs = CurrencyConverter.convert(
      amount: usd_value,
      from_currency: "USD",
      to_currency: "VES",
      on_date: on_date,
    )&.dig(:amount).to_d
    return 0.to_d unless usd_to_bs.positive?

    return usd_to_bs.round(2) if normalized_reference == "Bs"

    reference_rate_bs = reference_rate_to_bs_on_date(reference: normalized_reference, on_date: on_date)
    return 0.to_d unless reference_rate_bs.positive?

    (usd_to_bs / reference_rate_bs).round(2)
  end

  def reference_rate_to_bs_on_date(reference:, on_date:)
    scope = TasaCambio.where(description: reference)
    return 0.to_d if scope.blank?

    if on_date.present?
      historical_rate = scope
        .where("fecha_referencia <= ?", on_date)
        .order(fecha_referencia: :desc, created_at: :desc)
        .limit(1)
        .pick(:valor)
      return historical_rate.to_d if historical_rate.present?
    end

    latest_rate = scope.order(fecha_referencia: :desc, created_at: :desc).limit(1).pick(:valor)
    latest_rate.to_d
  end

  def build_currency_rows(latest_rates:, include_unidad_vi:)
    rows = [
      {
        value: "Bs",
        label: "Bolivar",
        symbol: "Bs",
        rate_bs: 1.to_d,
      },
    ]

    latest_rates.each do |rate|
      next if !include_unidad_vi && rate.description == "Unidad VI"

      rows << {
        value: rate.description,
        label: rate.description,
        symbol: rate.symbol.presence || TasaCambio::DEFAULT_SYMBOLS[rate.description] || rate.description,
        rate_bs: rate.valor.to_d,
      }
    end

    rows
  end

  def render_show_blocked(message)
    respond_to do |format|
      format.html do
        render partial: "services/show_blocked",
               locals: { message: message },
               status: :forbidden
      end
    end
  end
end
