class ServicesController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:services) }
  before_action :require_admin, except: %i[index show]
  before_action :set_service, only: %i[show edit update destroy]
  before_action :set_form_collections, only: %i[new create edit update]
  before_action :set_pending_cost_accounts,
                only: %i[pending_costs pending_cost_detail pay_pending_cost_line remove_pending_cost_line_payment]

  def index
    scoped_services = current_business
                      .services
                      .includes(:system_service, service_expense_structures: %i[
                        service_variable_expenses
                      ] + [
                        { service_manager_expenses: :manager },
                        { service_nested_expenses: :nested_service },
                        { service_product_expenses: [:product_variation,
                                                     { producto: :product_variations }] }
                      ])
    scoped_services = scoped_services.visible_for_user(Current.user)

    @active_query_text = params[:query_text].to_s.strip
    @active_system_filter = params[:system_filter].to_s.strip
    @active_status_filter = params[:status_filter].to_s.strip
    @active_status_filter = 'all' unless %w[all available unavailable caution
                                            restricted].include?(@active_status_filter)

    services_for_badges = scoped_services.reorder(nil)
    @services_total_count = services_for_badges.count
    @service_systems = services_for_badges
                       .joins(:system_service)
                       .group('system_services.name')
                       .count
                       .sort_by { |nombre, _cantidad| nombre.to_s.downcase }

    available_count = services_for_badges.where(available: true).count
    @service_status_counts = {
      available: available_count,
      unavailable: @services_total_count - available_count,
      caution: services_for_badges.where(caution_service: true).count,
      restricted: services_for_badges.where(restricted_service: true).count
    }

    @services = scoped_services

    query_active = @active_query_text.present?
    if query_active
      @services = @services
                  .whose_name_starts_with(@active_query_text)
    end

    if @active_system_filter.present?
      @services = @services
                  .joins(:system_service)
                  .where(system_services: { name: @active_system_filter })
    end

    @services = case @active_status_filter
                when 'available'
                  @services.where(available: true)
                when 'unavailable'
                  @services.where(available: false)
                when 'caution'
                  @services.where(caution_service: true)
                when 'restricted'
                  @services.where(restricted_service: true)
                else
                  @services
                end

    if query_active
      @services = @services.order('services.description ASC')
    else
      @services = @services.left_joins(:system_service)
      @services = @services.order('system_services.name ASC, services.description ASC')
    end

    @pagy, @services = pagy_countless(@services, items: 30)
  end

  def printing_prices
    @printing_services = current_business
                         .services
                         .includes(:system_service, :service_print_coverage_prices,
                                   :service_print_volume_discounts,
                                   service_print_material_surcharges: :producto)
                         .printing_type_candidates
                         .order(:description)

    @products_for_expenses = current_business.productos.includes(:product_variations).order(:descripcion)
    rate = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : 0.to_d
    @service_expenses_bcv_rate = rate.positive? ? rate : TasaCambio.latest_value('Dolar BCV').to_d
  end

  def update_printing_prices
    service = current_business
              .services
              .includes(:system_service, :service_print_coverage_prices, :service_print_material_surcharges)
              .find(params[:id])

    unless service.printing_type_service?
      return redirect_to printing_prices_services_path,
                         alert: 'Solo puedes configurar precios de impresion para servicios del sistema Impresion.'
    end

    if service.update(printing_prices_params)
      redirect_to printing_prices_services_path(anchor: "service-print-card-#{service.id}"),
                  notice: "Configuracion de impresion actualizada para #{service.description}."
    else
      redirect_to printing_prices_services_path(anchor: "service-print-card-#{service.id}"),
                  alert: service.errors.full_messages.to_sentence
    end
  end

  def recarga_parameters
    services_scope = current_business.services.includes(:system_service).where.not(system_service_id: nil)
    @recarga_services = services_scope.select { |service| service.system_service&.recarga_system? }
    @recarga_services.sort_by! { |service| service.description.to_s.downcase }
  end

  def update_recarga_parameters
    service = current_business.services.includes(:system_service).find(params[:id])

    unless service.system_service&.recarga_system?
      return redirect_to recarga_parameters_services_path,
                         alert: 'Solo puedes configurar recargas para servicios del sistema Recarga.'
    end

    if service.update(recarga_parameters_params)
      redirect_to recarga_parameters_services_path(anchor: "recarga-service-card-#{service.id}"),
                  notice: "Parametros de recarga actualizados para #{service.description}."
    else
      redirect_to recarga_parameters_services_path(anchor: "recarga-service-card-#{service.id}"),
                  alert: service.errors.full_messages.to_sentence
    end
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
                  .where(status: 'paid')
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
        (row[:nested_sale] ? 1 : 0)
      ]
    end

    @pending_cost_total_rows = sold_rows.size
    @pending_cost_total_quantity = sold_rows.sum { |row| row[:quantity].to_d }.round(2)
    @pending_cost_pending_count = sold_rows.count { |row| row[:cost_status] == 'pending' }
    @pending_cost_partial_count = sold_rows.count { |row| row[:cost_status] == 'partial' }
    @pending_cost_paid_count = sold_rows.count { |row| row[:cost_status] == 'paid' }
    @pending_cost_no_cost_count = sold_rows.count { |row| row[:cost_status] == 'no_cost' }
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
                         alert: 'No se encontro el registro de costo pendiente indicado.'
    end

    lines = normalized_pending_cost_lines_for(debt)
    if lines.empty?
      return redirect_to pending_costs_services_path,
                         alert: 'No hay detalles de costo disponibles para este registro.'
    end

    payable_lines = lines.select { |line| pending_cost_line_payable?(line) }
    pending_usd = payable_lines.sum { |line| line['pending_usd'].to_d }.round(2)
    paid_usd = payable_lines.sum { |line| line['paid_usd'].to_d }.round(2)
    total_usd = payable_lines.sum { |line| line['amount_usd'].to_d }.round(2)

    @pending_cost_row = {
      debt: debt,
      lines: lines,
      debt_currency: debt.currency.to_s.upcase,
      total_usd: total_usd,
      paid_usd: paid_usd,
      pending_usd: pending_usd,
      status: pending_cost_status_from_lines(payable_lines)
    }

    @pending_cost_payments_by_line = pending_cost_debt_payments_by_line(debt: debt)
    apply_pending_cost_detail_display_amounts!(
      lines: lines,
      debt: debt,
      payments_by_line: @pending_cost_payments_by_line
    )

    @pending_cost_currency_rates = build_pending_cost_currency_rates(rows: [@pending_cost_row],
                                                                     accounts: @pending_cost_accounts)
  end

  def pending_cost_rates
    reference_date = parse_pending_cost_payment_date(params[:fecha] || params[:date])
    return render json: { error: 'Fecha invalida' }, status: :unprocessable_entity if reference_date.blank?

    rates = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: reference_date).to_d.to_f
    end
    rates['VES'] = 1.0

    render json: {
      fecha_referencia: reference_date,
      rates: rates
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
                         alert: 'No se encontro la deuda pendiente de costos indicada.'
    end

    line_id = params[:line_id].to_s.strip
    lines = normalized_pending_cost_lines_for(debt)
    line = lines.find { |row| row['line_id'].to_s == line_id }

    if line.blank?
      return redirect_to redirect_path,
                         alert: 'No se encontro la clasificacion/estructura seleccionada.'
    end

    unless pending_cost_line_payable?(line)
      return redirect_to redirect_path,
                         alert: 'Esta linea es informativa y no requiere pago.'
    end

    pending_line_usd = line['pending_usd'].to_d.round(2)
    unless pending_line_usd.positive?
      return redirect_to redirect_path,
                         alert: 'La linea seleccionada ya se encuentra pagada.'
    end

    account = @pending_cost_accounts.find_by(id: params[:account_id])
    if account.blank?
      return redirect_to redirect_path,
                         alert: 'Selecciona una cuenta valida para registrar el pago.'
    end

    required_account_currency = pending_cost_expected_account_currency_for(
      line: line,
      debt_currency: debt.currency
    )
    if required_account_currency.present? && account.currency.to_s.upcase != required_account_currency
      required_label = pending_cost_expected_account_currency_label(required_account_currency)
      return redirect_to redirect_path,
                         alert: "Esta clasificacion solo permite pagos con cuentas en #{required_label}."
    end

    amount_original = parse_pending_cost_decimal(params[:amount])
    unless amount_original.positive?
      return redirect_to redirect_path,
                         alert: 'Indica un monto valido mayor a 0.'
    end

    payment_date = parse_pending_cost_payment_date(params[:payment_date])
    if payment_date.blank?
      return redirect_to redirect_path,
                         alert: 'Debes indicar una fecha valida para registrar el pago.'
    end

    payment_method = params[:payment_method].to_s.strip
    reference = params[:reference].to_s.strip

    if account.account_type == 'bank_account'
      unless %w[transfer mobile].include?(payment_method)
        return redirect_to redirect_path,
                           alert: 'Selecciona transferencia o pago movil para pagos bancarios.'
      end

      unless /^\d{4}$/.match?(reference)
        return redirect_to redirect_path,
                           alert: 'La referencia bancaria debe tener exactamente 4 digitos.'
      end
    else
      payment_method = nil
      reference = nil
    end

    include_commission = ActiveModel::Type::Boolean.new.cast(params[:include_commission])
    commission_amount = parse_pending_cost_decimal(params[:commission_amount])
    commission_amount = 0.to_d unless commission_amount.positive?

    if include_commission && commission_amount <= 0 && amount_original.positive?
      commission_amount = (amount_original * 0.003).round(2)
    end

    if include_commission && commission_amount.negative?
      return redirect_to redirect_path,
                         alert: 'La comision no puede ser negativa.'
    end

    conversion = CurrencyConverter.convert(
      amount: amount_original,
      from_currency: account.currency,
      to_currency: debt.currency,
      on_date: payment_date
    )

    if conversion.blank?
      return redirect_to redirect_path,
                         alert: 'No se pudo convertir el pago a la moneda de la deuda.'
    end

    amount_in_debt_currency = conversion[:amount].to_d.round(2)
    payment_scope = params[:payment_scope].to_s
    force_total_settlement = ActiveModel::Type::Boolean.new.cast(params[:force_total_settlement]) ||
                             payment_scope == 'total'

    if !force_total_settlement && amount_in_debt_currency > pending_line_usd + 0.01.to_d
      return redirect_to redirect_path,
                         alert: 'El pago excede el saldo pendiente de la clasificacion seleccionada.'
    end

    update_source_cost_override = params[:update_source_cost_override]
    update_source_cost = if update_source_cost_override.present?
                           ActiveModel::Type::Boolean.new.cast(update_source_cost_override)
                         else
                           ActiveModel::Type::Boolean.new.cast(params[:update_source_cost])
                         end

    amount_applied_to_line = force_total_settlement ? pending_line_usd : amount_in_debt_currency

    Debt.transaction do
      line['paid_usd'] = (line['paid_usd'].to_d + amount_applied_to_line).round(2).to_f
      line['pending_usd'] = (line['amount_usd'].to_d - line['paid_usd'].to_d).round(2).to_f
      line['pending_usd'] = 0.0 if line['pending_usd'].to_d.abs <= 0.01.to_d
      line['status'] = if line['pending_usd'].to_d <= 0
                         'paid'
                       elsif line['paid_usd'].to_d.positive?
                         'partial'
                       else
                         'pending'
                       end

      if update_source_cost
        source_snapshot = update_pending_cost_source_row!(
          line: line,
          amount_usd: amount_applied_to_line,
          paid_amount_original: amount_original,
          paid_currency: account.currency,
          on_date: payment_date
        )
        apply_pending_cost_source_snapshot!(line: line, snapshot: source_snapshot, debt: debt)
      else
        lock_paid_pending_cost_line_snapshot!(
          line: line,
          paid_amount_original: amount_original,
          paid_currency: account.currency,
          on_date: payment_date
        )
      end

      paid_usd = lines.sum { |row| row['paid_usd'].to_d }.round(2)
      pending_usd = lines.sum { |row| row['pending_usd'].to_d }.round(2)
      overall_status = if pending_usd <= 0.01.to_d
                         'paid'
                       elsif paid_usd.positive?
                         'partial'
                       else
                         'pending'
                       end

      details = debt.service_cost_details_hash.deep_dup
      details['version'] ||= 1
      details['service_id'] ||= debt.service_id
      details['service_name'] ||= debt.service&.description.to_s
      details['total_usd'] = lines.sum { |row| row['amount_usd'].to_d }.round(2).to_f
      details['paid_usd'] = paid_usd.to_f
      details['pending_usd'] = pending_usd.to_f
      details['status'] = overall_status
      details['lines'] = lines

      debt.update!(
        service_cost_details: details,
        service_cost_pending: pending_usd.positive?
      )

      movement_occurred_at = pending_cost_movement_occurred_at(payment_date)

      payment = debt.debt_payments.create!(
        account: account,
        amount: amount_original,
        currency: account.currency,
        payment_method: payment_method,
        reference: reference,
        occurred_at: payment_date,
        movement_occurred_at_override: movement_occurred_at,
        notes: "Pago costo servicio [DEBT:#{debt.id}] [LINE:#{line_id}]"
      )

      if force_total_settlement
        effective_rate = if amount_original.to_d.positive?
                           (amount_applied_to_line / amount_original.to_d).round(8)
                         else
                           conversion[:rate].to_d
                         end

        payment.update_columns(
          amount_in_debt_currency: amount_applied_to_line.to_d,
          exchange_rate_to_debt_currency: effective_rate,
          updated_at: Time.current
        )
      end

      if include_commission && commission_amount.positive? && account.account_type == 'bank_account'
        commission_description = if payment_method == 'mobile'
                                   'Comision de pago movil'
                                 else
                                   'Comision de transferencia'
                                 end

        account.account_movements.create!(
          movement_kind: 'expense',
          amount: commission_amount,
          description: "#{commission_description} [DEBT:#{debt.id}] [LINE:#{line_id}] [DP:#{payment.id}] [COMMISSION]",
          occurred_at: movement_occurred_at,
          payment_method: pending_cost_account_movement_method(payment_method),
          reference: reference.presence
        )
      end

      sync_paid_service_cost_snapshot_to_sale!(debt: debt, details: details) if pending_usd <= 0.01.to_d
    end

    redirect_to pending_cost_redirect_path(debt: debt),
                notice: 'Pago registrado en la linea de costo seleccionada.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to pending_cost_redirect_path(debt: debt),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def remove_pending_cost_line_payment
    debt = current_business
           .debts
           .includes(debt_payments: :account)
           .find_by(id: params[:debt_id])

    redirect_path = pending_cost_redirect_path(debt: debt)

    unless debt&.payable? && debt.service_cost_record?
      return redirect_to pending_costs_services_path,
                         alert: 'No se encontro el registro de costo pendiente indicado.'
    end

    payment = debt.debt_payments.find_by(id: params[:payment_id])
    if payment.blank?
      return redirect_to redirect_path,
                         alert: 'No se encontro el pago seleccionado.'
    end

    line_id = pending_cost_line_id_from_payment_notes(payment.notes)
    if line_id.blank?
      return redirect_to redirect_path,
                         alert: 'El pago no esta asociado a una linea de costo eliminable.'
    end

    requested_line_id = params[:line_id].to_s.strip
    if requested_line_id.present? && requested_line_id != line_id
      return redirect_to redirect_path,
                         alert: 'La linea indicada no coincide con el pago seleccionado.'
    end

    lines = normalized_pending_cost_lines_for(debt)
    line = lines.find { |row| row['line_id'].to_s == line_id }
    if line.blank?
      return redirect_to redirect_path,
                         alert: 'No se encontro la linea asociada al pago seleccionado.'
    end

    unless pending_cost_line_payable?(line)
      return redirect_to redirect_path,
                         alert: 'La linea asociada es informativa y no admite eliminacion de pagos.'
    end

    amount_applied_to_line = payment.amount_in_debt_currency.to_d.round(2)

    Debt.transaction do
      updated_paid_usd = (line['paid_usd'].to_d - amount_applied_to_line).round(2)
      updated_paid_usd = 0.to_d if updated_paid_usd.negative?

      amount_usd = line['amount_usd'].to_d.round(2)
      pending_usd = (amount_usd - updated_paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      line['paid_usd'] = updated_paid_usd.to_f
      line['pending_usd'] = pending_usd.to_f
      line['status'] = if pending_usd <= 0
                         'paid'
                       elsif updated_paid_usd.positive?
                         'partial'
                       else
                         'pending'
                       end

      paid_usd = lines.sum { |row| row['paid_usd'].to_d }.round(2)
      total_usd = lines.sum { |row| row['amount_usd'].to_d }.round(2)
      pending_usd_total = (total_usd - paid_usd).round(2)
      pending_usd_total = 0.to_d if pending_usd_total.abs <= 0.01.to_d

      details = debt.service_cost_details_hash.deep_dup
      details['version'] ||= 1
      details['service_id'] ||= debt.service_id
      details['service_name'] ||= debt.service&.description.to_s
      details['total_usd'] = total_usd.to_f
      details['paid_usd'] = paid_usd.to_f
      details['pending_usd'] = pending_usd_total.to_f
      details['status'] = pending_cost_status_from_lines(lines)
      details['lines'] = lines

      pending_cost_account_movements_for_payment(payment: payment, debt: debt, line: line).each(&:destroy!)
      payment.destroy!

      debt.update!(
        service_cost_details: details,
        service_cost_pending: pending_usd_total.positive?
      )

      sync_paid_service_cost_snapshot_to_sale!(debt: debt, details: details)
    end

    redirect_to redirect_path,
                notice: 'Pago eliminado correctamente de la linea seleccionada.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to pending_cost_redirect_path(debt: debt),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def new
    @service = current_business.services.new(pricing_mode: :fixed, currency_base_price: 'Dolar BCV')
  end

  def create
    @service = current_business.services.new(service_params)

    if @service.save
      redirect_to services_path, notice: 'Servicio creado exitosamente.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    unless @service.show_allowed_for?(Current.user)
      return render_show_blocked(
        @service.restricted_service? ? 'Este servicio esta restringido y solo puede verlo el administrador.' : 'Este servicio no esta disponible en este momento.'
      )
    end

    respond_to do |format|
      format.html { render partial: 'services/show', locals: { service: @service } }
    end
  end

  def export_excel
    services = current_business
               .services
               .includes(:system_service, service_managers: :manager)
               .order('system_services.name ASC NULLS LAST, services.description ASC')
               .references(:system_service)

    rates = TasaCambio.pluck(:description, :valor).to_h
    tasa_dolar_bcv = rates['Dolar BCV'].to_f

    headers = [
      'Servicio ID',
      'Descripcion',
      'System Service',
      'Disponible',
      'Moneda base precio',
      'Precio venta',
      'Unidades valor',
      'Costo habilitado',
      'Requisitos fisicos',
      'Requisitos digitales',
      'Datos requeridos',
      'Pasos personal',
      'Nota',
      'Contenido entrega',
      'Tiempo entrega',
      'Creado en',
      'Actualizado en',
      'Manager',
      'Referencia costo',
      'Costo manager (referencia)',
      'Costo manager (USD estimado)'
    ]

    table_head = headers.map { |header| "<th>#{sanitize_excel_cell(header)}</th>" }.join

    table_rows = services.flat_map do |service|
      service_rows = []
      managers = service.service_managers.to_a

      if managers.empty?
        service_rows << build_service_export_row(service, nil, nil, nil)
      else
        managers.each do |service_manager|
          reference_rate = rates[service_manager.reference_cost].to_f
          manager_cost_usd = if service_manager.cost.present? && reference_rate.positive? && tasa_dolar_bcv.positive?
                               (service_manager.cost.to_f * reference_rate / tasa_dolar_bcv).round(2)
                             end

          service_rows << build_service_export_row(
            service,
            service_manager.manager&.name,
            service_manager.reference_cost,
            service_manager.cost,
            manager_cost_usd
          )
        end
      end

      service_rows
    end.join

    html = <<~HTML
      <html>
        <head>
          <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        </head>
        <body>
          <table border="1">
            <thead>
              <tr>#{table_head}</tr>
            </thead>
            <tbody>
              #{table_rows}
            </tbody>
          </table>
        </body>
      </html>
    HTML

    filename = "servicios_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xls"
    send_data html,
              filename: filename,
              type: 'application/vnd.ms-excel; charset=utf-8',
              disposition: 'attachment'
  end

  def edit
    @service.service_expense_structures.build if @service.cost && @service.service_expense_structures.empty?
  end

  def update
    updated = false
    impacted_debts = pending_service_cost_debts_for_structure_sync(service: @service)
    previous_consumptions_by_debt = pending_service_consumptions_for_debts(debts: impacted_debts)
    update_attrs = service_params

    Service.transaction do
      if should_reset_active_expense_structures_before_update?(update_attrs)
        @service.service_expense_structures.where(active_for_sales: true).update_all(active_for_sales: false,
                                                                                     updated_at: Time.current)
      end

      updated = @service.update(update_attrs)
      raise ActiveRecord::Rollback unless updated

      references_synced = sync_expense_reference_from_raw_params!(
        service: @service,
        raw_service: params[:service]
      )

      unless references_synced
        updated = false
        raise ActiveRecord::Rollback
      end

      inventory_synced = sync_pending_service_consumables_inventory!(
        debts: impacted_debts,
        previous_consumptions_by_debt: previous_consumptions_by_debt
      )

      unless inventory_synced
        updated = false
        raise ActiveRecord::Rollback
      end
    end

    if updated
      redirect_to services_path, notice: 'Servicio actualizado exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @service.destroy
      redirect_to services_path, notice: 'Service deleted successfully.'
    else
      redirect_to services_path, alert: 'Failed to delete the service.'
    end
  end

  private

  def build_service_export_row(service, manager_name, reference_cost, manager_cost, manager_cost_usd = nil)
    values = [
      service.id,
      service.description,
      service.system_service&.name,
      service.available? ? 'Si' : 'No',
      service.currency_base_price,
      service.sale_price,
      service.value_units,
      service.cost ? 'Si' : 'No',
      service.physical_requirements,
      service.digital_requirements,
      service.required_data,
      service.personal_steps,
      service.note,
      service.delivery_content,
      service.delivery_time,
      service.created_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S'),
      service.updated_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S'),
      manager_name,
      reference_cost,
      manager_cost,
      manager_cost_usd
    ]

    cells = values.map { |value| "<td>#{sanitize_excel_cell(value)}</td>" }.join
    "<tr>#{cells}</tr>"
  end

  def sanitize_excel_cell(value)
    ERB::Util.html_escape(value.to_s.gsub(/[\r\n]/, ' ').strip)
  end

  def set_service
    @service = current_business
               .services
               .includes(:service_print_coverage_prices,
                         :service_print_material_surcharges,
                         :print_delivery_service,
                         :print_delivery_material_surcharge)
               .includes(:system_service, service_expense_structures: %i[
                 service_variable_expenses
               ] + [
                 { service_manager_expenses: :manager },
                 { service_nested_expenses: :nested_service },
                 { service_product_expenses: [:product_variation,
                                              { producto: :product_variations }] }
               ])
               .find(params[:id])
  end

  def set_form_collections
    @managers = Manager.order(:name)
    @products_for_expenses = if current_business.present?
                               current_business.productos.includes(:product_variations, :stock_lots).order(:descripcion)
                             else
                               Producto.none
                             end

    scope = current_business.services.includes(:system_service).where(nested_available: true).order(:description)
    @nested_services_for_expenses = @service&.id.present? ? scope.where.not(id: @service.id) : scope

    rate = @tasa_dolar_bcv.is_a?(Numeric) ? @tasa_dolar_bcv.to_d : 0.to_d
    @service_expenses_bcv_rate = rate.positive? ? rate : TasaCambio.latest_value('Dolar BCV').to_d

    latest_rates = TasaCambio.latest_by_description
    @expense_currency_rows = build_currency_rows(latest_rates: latest_rates, include_unidad_vi: false)
    @service_price_currency_rows = build_currency_rows(latest_rates: latest_rates, include_unidad_vi: true)

    @print_type_services = current_business
                           .services
                           .includes(:service_print_coverage_prices, service_print_material_surcharges: :producto)
                           .printing_type_candidates
                           .order(:description)

    @print_type_services_payload = @print_type_services.each_with_object([]) do |service, rows|
      rows << {
        id: service.id,
        name: service.description.to_s,
        coverage_prices: service.service_print_coverage_prices
                         .ordered_by_coverage
                                .map do |price_row|
                                  {
                                    coverage_percent: price_row.coverage_percent.to_d.to_f,
                                    price_bs: price_row.price_bs.to_d.to_f
                                  }
                                end,
        material_options: service.service_print_material_surcharges
                          .sort_by { |row| [row.created_at || Time.at(0), row.id.to_i] }
                                 .map do |material_row|
                                   {
                                     id: material_row.id,
                                     label: material_row.display_label.to_s,
                                     product_id: material_row.producto_id,
                                     product_name: material_row.producto&.descripcion.to_s
                                   }
                                 end
      }
    end

    @lamination_services = current_business
                           .services
                           .joins(:system_service)
                           .where('system_services.name ILIKE :q1 OR system_services.name ILIKE :q2',
                                  q1: '%plastificacion%',
                                  q2: '%plastificación%')
                           .order(:description)

    @lamination_services_payload = @lamination_services.map do |service|
      {
        id: service.id,
        name: service.description.to_s
      }
    end

    @rcv_system_service_ids = SystemService.order(:id).select(&:rcv_system?).map(&:id)
    @rcv_shared_template = Service.rcv_shared_template_attributes_for_business(current_business)
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
      :delivery_physical_enabled,
      :delivery_digital_enabled,
      :warn_digital_only_delivery_in_sales,
      :use_custom_image_for_display,
      :custom_display_image,
      :print_delivery_service_id,
      :print_delivery_material_surcharge_id,
      :print_delivery_pages,
      :print_delivery_extra_products,
      :system_service_id,
      :physical_requirements,
      :digital_requirements,
      :required_data,
      :personal_steps,
      :note,
      :delivery_content,
      :delivery_time,
      :available,
      service_print_coverage_prices_attributes: %i[id coverage_percent price_bs _destroy],
      service_print_material_surcharges_attributes: %i[id producto_id description surcharge_percent
                                                       required_quantity
                                                       include_product_price_in_sale _destroy],
      service_managers_attributes: %i[id manager_id cost reference_cost _destroy],
      service_expense_structures_attributes: [
        :id,
        :description,
        :active_for_sales,
        :_destroy,
        { service_manager_expenses_attributes: %i[id manager_id currency_reference amount_reference amount_usd
                                                  amount_bs _destroy] },
        { service_variable_expenses_attributes: %i[id description currency_reference amount_reference amount_usd
                                                   amount_bs _destroy] }
      ]
    )

    merge_expense_reference_fields!(permitted: permitted, raw_service: raw_service)
    normalize_active_expense_structure_flags!(permitted: permitted)
    normalize_print_delivery_pages_param!(permitted: permitted)
    normalize_print_delivery_extra_products_param!(permitted: permitted)

    unless Service.column_names.include?('print_delivery_extra_products')
      permitted.delete(:print_delivery_extra_products)
    end

    permitted[:nested_available] = false

    unless ActiveModel::Type::Boolean.new.cast(permitted[:cost])
      permitted.delete(:service_expense_structures_attributes)
    end

    permitted
  end

  def printing_prices_params
    params
      .require(:service)
      .permit(
        :print_sale_description,
        service_print_coverage_prices_attributes: %i[id coverage_percent price_bs _destroy],
        service_print_volume_discounts_attributes: %i[id min_quantity discount_percent _destroy],
        service_print_material_surcharges_attributes: %i[id producto_id description surcharge_percent
                                                         required_quantity
                                                         include_product_price_in_sale _destroy]
      )
  end

  def recarga_parameters_params
    params.require(:service).permit(
      :recarga_image,
      :recarga_min_amount,
      :recarga_multiple_amount,
      :recarga_profit_percent
    )
  end

  def normalize_print_delivery_pages_param!(permitted:)
    raw_pages = permitted[:print_delivery_pages]
    return if raw_pages.is_a?(Array)
    return if raw_pages.is_a?(ActionController::Parameters)

    parsed = if raw_pages.is_a?(String)
               begin
                 JSON.parse(raw_pages)
               rescue JSON::ParserError
                 []
               end
             else
               []
             end

    permitted[:print_delivery_pages] = parsed.is_a?(Array) ? parsed : []
  end

  def normalize_print_delivery_extra_products_param!(permitted:)
    raw_rows = permitted[:print_delivery_extra_products]
    return if raw_rows.is_a?(Array)
    return if raw_rows.is_a?(ActionController::Parameters)

    parsed = if raw_rows.is_a?(String)
               begin
                 JSON.parse(raw_rows)
               rescue JSON::ParserError
                 []
               end
             else
               []
             end

    permitted[:print_delivery_extra_products] = parsed.is_a?(Array) ? parsed : []
  end

  def merge_expense_reference_fields!(permitted:, raw_service:)
    permitted_structures = permitted[:service_expense_structures_attributes]
    raw_structures = raw_service[:service_expense_structures_attributes]

    return unless permitted_structures.respond_to?(:each)
    return unless raw_structures.respond_to?(:[])

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_manager_expenses_attributes
    )

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_variable_expenses_attributes
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

        currency_reference = raw_row[:currency_reference] || raw_row['currency_reference']
        amount_reference = raw_row[:amount_reference] || raw_row['amount_reference']
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
                     raw_service&.[]('service_expense_structures_attributes')

    return true unless raw_structures.respond_to?(:each)

    success = true

    raw_structures.each do |_structure_key, raw_structure|
      next unless raw_structure.respond_to?(:[])

      structure_id = raw_structure[:id] || raw_structure['id']
      next if structure_id.blank?

      structure = service.service_expense_structures.find_by(id: structure_id)
      next unless structure

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_manager_expenses,
        raw_rows: raw_structure[:service_manager_expenses_attributes] || raw_structure['service_manager_expenses_attributes']
      )

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_variable_expenses,
        raw_rows: raw_structure[:service_variable_expenses_attributes] || raw_structure['service_variable_expenses_attributes']
      )
    end

    success
  end

  def sync_nested_expense_reference_rows!(scope:, raw_rows:)
    return true unless raw_rows.respond_to?(:each)

    success = true

    raw_rows.each do |_row_key, raw_row|
      next unless raw_row.respond_to?(:[])

      destroy_flag = ActiveModel::Type::Boolean.new.cast(raw_row[:_destroy] || raw_row['_destroy'])
      next if destroy_flag

      row_id = raw_row[:id] || raw_row['id']
      next if row_id.blank?

      record = scope.find_by(id: row_id)
      next unless record

      attrs = {}
      currency_reference = raw_row[:currency_reference] || raw_row['currency_reference']
      amount_reference = raw_row[:amount_reference] || raw_row['amount_reference']

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

  def normalize_active_expense_structure_flags!(permitted:)
    structures = permitted[:service_expense_structures_attributes]
    return unless structures.respond_to?(:each)

    active_structure_key = nil

    structures.each do |structure_key, raw_structure|
      next unless raw_structure.respond_to?(:[])

      destroy_flag = ActiveModel::Type::Boolean.new.cast(raw_structure[:_destroy] || raw_structure['_destroy'])
      next if destroy_flag

      active_flag = ActiveModel::Type::Boolean.new.cast(raw_structure[:active_for_sales] || raw_structure['active_for_sales'])
      active_structure_key = structure_key if active_flag
    end

    return if active_structure_key.nil?

    structures.each do |structure_key, raw_structure|
      next unless raw_structure.respond_to?(:[])

      raw_structure[:active_for_sales] = (structure_key.to_s == active_structure_key.to_s)
    end
  end

  def should_reset_active_expense_structures_before_update?(update_attrs)
    structures = update_attrs[:service_expense_structures_attributes]
    return false unless structures.respond_to?(:each)

    selected_active_id = nil

    structures.each do |_structure_key, raw_structure|
      next unless raw_structure.respond_to?(:[])

      destroy_flag = ActiveModel::Type::Boolean.new.cast(raw_structure[:_destroy] || raw_structure['_destroy'])
      next if destroy_flag

      active_flag = ActiveModel::Type::Boolean.new.cast(raw_structure[:active_for_sales] || raw_structure['active_for_sales'])
      next unless active_flag

      selected_active_id = (raw_structure[:id] || raw_structure['id']).to_s.strip.presence
      break
    end

    return false if selected_active_id.blank?

    active_ids = @service
                 .service_expense_structures
                 .where(active_for_sales: true)
                 .pluck(:id)
                 .map(&:to_s)

    return false if active_ids.empty?
    return false if active_ids.size == 1 && active_ids.include?(selected_active_id)

    true
  end

  def pending_service_cost_debts_for_structure_sync(service:)
    impacted_service_ids = impacted_service_ids_for_structure_sync(service: service)
    return [] if impacted_service_ids.empty?

    current_business
      .debts
      .where(debt_kind: 'payable', service_cost_pending: true, service_id: impacted_service_ids)
      .where.not(venta_id: nil)
      .to_a
  end

  def impacted_service_ids_for_structure_sync(service:)
    return [] if service.blank?

    [service.id.to_i].uniq
  end

  def pending_service_consumptions_for_debts(debts:)
    service_ids = Array(debts).map(&:service_id).compact.uniq
    return {} if service_ids.empty?

    services_by_id = services_for_consumable_sync(service_ids: service_ids)

    Array(debts).each_with_object({}) do |debt, hash|
      hash[debt.id] = expected_consumables_for_debt(
        debt: debt,
        services_by_id: services_by_id
      )
    end
  end

  def services_for_consumable_sync(service_ids:)
    current_business
      .services
      .where(id: service_ids)
      .includes(
        { service_expense_structures: { service_product_expenses: [:product_variation,
                                                                   { producto: :product_variations }] } }
      )
      .index_by(&:id)
  end

  def expected_consumables_for_debt(debt:, services_by_id:)
    service = services_by_id[debt.service_id]
    return {} if service.blank?

    multiplier = debt.service_cost_details_hash['quantity'].to_d
    multiplier = 1.to_d unless multiplier.positive?

    collect_service_consumables_for_sync(
      service: service,
      multiplier: multiplier,
      visited_service_ids: []
    )
  end

  def collect_service_consumables_for_sync(service:, multiplier:, visited_service_ids:)
    return {} if service.blank?
    return {} unless multiplier.to_d.positive?
    return {} if visited_service_ids.include?(service.id)

    grouped = Hash.new(0.to_d)

    service.service_expense_structures.each do |structure|
      next unless ActiveModel::Type::Boolean.new.cast(structure.active_for_sales)

      structure.service_product_expenses.each do |expense|
        producto = expense.producto
        next unless producto
        next unless producto.business_id == current_business.id

        variation = expense.product_variation
        variation ||= producto.product_variations.min_by(&:id)
        next if variation.blank?

        quantity = expense.quantity.to_d * multiplier.to_d
        next unless quantity.positive?

        key = [producto.id.to_i, variation.id.to_i]
        grouped[key] += quantity
      end
    end

    grouped
  end

  def sync_pending_service_consumables_inventory!(debts:, previous_consumptions_by_debt:)
    return true if debts.blank?

    current_consumptions_by_debt = pending_service_consumptions_for_debts(debts: debts)
    sale_deltas = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }

    debts.each do |debt|
      previous_map = previous_consumptions_by_debt[debt.id] || {}
      current_map = current_consumptions_by_debt[debt.id] || {}

      (previous_map.keys | current_map.keys).each do |key|
        previous_quantity = previous_map[key].to_d
        current_quantity = current_map[key].to_d
        delta = (current_quantity - previous_quantity).round(4)
        next if delta.abs <= 0.0001.to_d

        product_id, variation_id = key
        if delta.positive?
          consume_service_stock_delta!(
            product_id: product_id,
            variation_id: variation_id,
            quantity_units: delta,
            debt: debt
          )
        else
          restore_service_stock_delta!(
            product_id: product_id,
            variation_id: variation_id,
            quantity_units: delta.abs,
            debt: debt
          )
        end

        sale_deltas[debt.venta_id][key] += delta
      end
    end

    apply_service_consumable_deltas_to_sale_notes!(sale_deltas: sale_deltas)
    true
  rescue ActiveRecord::RecordInvalid => e
    @service.errors.add(:base, e.message)
    false
  end

  def consume_service_stock_delta!(product_id:, variation_id:, quantity_units:, debt:)
    producto = current_business.productos.find_by(id: product_id)
    return if producto.blank?

    producto.consume_variation_stock!(variation_id: variation_id, quantity_units: quantity_units)
  rescue ActiveRecord::RecordInvalid => e
    raise ActiveRecord::RecordInvalid.new(@service),
          "No se pudo descontar inventario del servicio pendiente (deuda ##{debt.id}): #{e.message}"
  end

  def restore_service_stock_delta!(product_id:, variation_id:, quantity_units:, debt:)
    producto = current_business.productos.find_by(id: product_id)
    return if producto.blank?

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

    raise ActiveRecord::RecordInvalid.new(@service),
          "No se pudo restaurar todo el inventario del servicio pendiente (deuda ##{debt.id}, faltan #{remaining_to_restore.to_f.round(4)} unidades)."
  end

  def apply_service_consumable_deltas_to_sale_notes!(sale_deltas:)
    sale_deltas.each do |sale_id, deltas|
      next if sale_id.blank?
      next if deltas.blank?

      sale = current_business.ventas.find_by(id: sale_id)
      next if sale.blank?

      notes_payload = begin
        parsed = JSON.parse(sale.notes.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      grouped_reserved = Hash.new(0.to_d)
      Array(notes_payload['reserved_service_products']).each do |row|
        next unless row.is_a?(Hash)

        product_id = row['product_id'].to_i
        variation_id = row['variation_id'].to_i
        quantity = row['quantity'].to_d
        next unless product_id.positive? && variation_id.positive?

        grouped_reserved[[product_id, variation_id]] += quantity
      end

      deltas.each do |key, delta|
        grouped_reserved[key] += delta.to_d
      end

      normalized_rows = grouped_reserved.each_with_object([]) do |(key, quantity), rows|
        next unless quantity.positive?

        product_id, variation_id = key
        rows << {
          'product_id' => product_id,
          'variation_id' => variation_id,
          'quantity' => quantity.round(4).to_f
        }
      end

      notes_payload['reserved_service_products'] = normalized_rows
      sale.update!(notes: notes_payload.to_json)
    end
  end

  def set_pending_cost_accounts
    @pending_cost_accounts = current_business.accounts.where(active: true).order(:currency, :name)
  end

  def pending_cost_filters_from_params
    {
      query_text: params[:query_text].to_s.strip,
      fecha_desde: parse_pending_cost_filter_date(params[:fecha_desde]),
      fecha_hasta: parse_pending_cost_filter_date(params[:fecha_hasta]),
      system_service_id: parse_pending_cost_filter_integer(params[:system_service_id]),
      manager_id: parse_pending_cost_filter_integer(params[:manager_id])
    }
  end

  def parse_pending_cost_filter_integer(value)
    parsed = value.to_i
    parsed.positive? ? parsed : nil
  end

  def parse_pending_cost_filter_date(value)
    return nil if value.blank?

    raw = value.to_s.strip
    return Date.strptime(raw, '%d-%m-%Y') if raw.match?(/\A\d{2}-\d{2}-\d{4}\z/)

    Date.iso8601(raw)
  rescue ArgumentError
    nil
  end

  def apply_pending_cost_sales_date_filters(scope:, filters:)
    filtered_scope = scope

    if filters[:fecha_desde].present?
      filtered_scope = filtered_scope.where('DATE(ventas.created_at) >= ?', filters[:fecha_desde])
    end

    if filters[:fecha_hasta].present?
      filtered_scope = filtered_scope.where('DATE(ventas.created_at) <= ?', filters[:fecha_hasta])
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
        Array(settlement['detail_lines']).each do |raw_line|
          line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}
          next unless line['classification'].to_s == 'nested_expense'
          next unless line['source_type'].to_s == 'ServiceNestedExpense'

          source_id = line['source_id'].to_i
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
      sale_printings = pending_cost_printing_sales_for_sale(sale: sale)
      printing_row_key_map = {}
      settlement_queue_by_name = Hash.new { |hash, key| hash[key] = [] }
      sale_settlements.each do |settlement|
        key = normalized_pending_cost_lookup_value(settlement['service_name'])
        next if key.blank?

        settlement_queue_by_name[key] << settlement
      end

      sale_payable_debts = sale.service_cost_debts.select(&:payable?)
      debts_by_service_id = sale_payable_debts.group_by(&:service_id)
      debts_by_snapshot_service_id = sale_payable_debts.group_by do |debt|
        snapshot_service_id = debt.service_cost_details_hash['service_id'].to_i
        snapshot_service_id.positive? ? snapshot_service_id : nil
      end
      debts_by_service_name = sale_payable_debts.group_by do |debt|
        normalized_pending_cost_lookup_value(
          debt.service_cost_details_hash['service_name'].presence || debt.service&.description
        )
      end

      settlement_queue_by_service_id = Hash.new { |hash, key| hash[key] = [] }
      sale_settlements.each do |settlement|
        service_id = settlement['service_id'].to_i
        next unless service_id.positive?

        settlement_queue_by_service_id[service_id] << settlement
      end

      service_item_groups = sale
                            .venta_items
                            .select { |item| item.producto_id.blank? }
                            .group_by do |item|
        [
          normalized_pending_cost_lookup_value(item.product_name),
          normalized_pending_cost_lookup_value(item.variation_name)
        ]
      end

      service_item_groups.each do |(name_key, _system_key), grouped_items|
        next if grouped_items.blank?

        first_item = grouped_items.first
        service_name_snapshot = first_item.product_name.to_s.strip.presence || 'Servicio'
        system_name_snapshot = first_item.variation_name.to_s.strip
        quantity = grouped_items.sum { |item| item.quantity.to_d }.round(2)
        quantity = 1.to_d unless quantity.positive?
        subtotal_usd = grouped_items.sum { |item| item.subtotal_usd.to_d }.round(2)
        unit_price_usd = (subtotal_usd / quantity).round(2)

        settlement = settlement_queue_by_name[name_key].shift

        resolved_service = resolve_pending_cost_service_for_snapshot(
          service_name: service_name_snapshot,
          system_name: system_name_snapshot,
          lookup: service_lookup
        )
        settlement_service_id = settlement.is_a?(Hash) ? settlement['service_id'].to_i : 0
        if resolved_service.blank? && settlement_service_id.positive?
          resolved_service = services_by_id[settlement_service_id]
        end
        if settlement.blank? && resolved_service&.id.present?
          settlement = settlement_queue_by_service_id[resolved_service.id].shift
        end

        debt = (debts_by_service_id[resolved_service.id]&.max_by(&:id) if resolved_service&.id.present?)
        debt ||= (debts_by_snapshot_service_id[resolved_service.id]&.max_by(&:id) if resolved_service&.id.present?)
        debt ||= debts_by_service_name[name_key]&.max_by(&:id)

        status_payload = pending_cost_status_for_direct_row(
          service: resolved_service,
          settlement: settlement,
          debt: debt,
          quantity: quantity
        )

        rows << {
          sale_id: sale.id,
          sold_at: sale.created_at,
          nested_sale: false,
          parent_service_name: nil,
          parent_service_system_name: nil,
          service_id: resolved_service&.id,
          service_name: service_name_snapshot,
          service_system_name: resolved_service&.system_service&.name.to_s.strip.presence || system_name_snapshot,
          system_service_id: resolved_service&.system_service_id,
          quantity: quantity,
          sale_unit_price_usd: unit_price_usd,
          sale_total_usd: subtotal_usd,
          agreed_price_usd: resolved_service&.to_agree? ? unit_price_usd : nil,
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
            sale.id
          ].join(' ').downcase
        }
      end

      sale_settlements.each do |settlement|
        parent_service_name = settlement['service_name'].to_s.strip
        parent_name_key = normalized_pending_cost_lookup_value(parent_service_name)
        parent_service = services_by_id[settlement['service_id'].to_i]
        if parent_service.blank?
          parent_service = resolve_pending_cost_service_for_snapshot(
            service_name: parent_service_name,
            system_name: nil,
            lookup: service_lookup
          )
        end

        parent_debt = (debts_by_service_id[parent_service.id]&.max_by(&:id) if parent_service&.id.present?)
        parent_debt ||= debts_by_service_name[parent_name_key]&.max_by(&:id)

        debt_lines_by_id = if parent_debt.present?
                             normalized_pending_cost_lines_for(parent_debt).index_by { |line| line['line_id'].to_s }
                           else
                             {}
                           end

        Array(settlement['detail_lines']).each do |raw_line|
          line = raw_line.is_a?(Hash) ? raw_line.deep_stringify_keys : {}

          if line['classification'].to_s == 'printing_expense'
            line_total_usd = line['amount_usd'].to_d.round(2)
            next unless line_total_usd.positive?

            line_quantity = line['quantity'].to_d.round(2)
            line_quantity = 1.to_d unless line_quantity.positive?
            line_unit_usd = (line_total_usd / line_quantity).round(2)

            print_service = services_by_id[line['source_id'].to_i]
            status_payload = pending_cost_status_for_printing_row(
              settlement: settlement,
              debt_line: debt_lines_by_id[line['line_id'].to_s],
              line_amount_usd: line_total_usd
            )

            parent_label = parent_service_name.presence || 'Servicio'
            print_label_raw = line['source_name'].to_s.strip.presence || 'Impresion fisica'
            print_label = pending_cost_child_service_display_name(
              service: print_service,
              fallback_name: print_label_raw,
              classification: line['classification']
            )

            rows << {
              sale_id: sale.id,
              sold_at: sale.created_at,
              nested_sale: false,
              printing_sale: true,
              parent_service_name: parent_label,
              parent_service_system_name: parent_service&.system_service&.name.to_s.strip.presence,
              service_id: print_service&.id,
              service_name: print_label,
              service_system_name: print_service&.system_service&.name.to_s.strip.presence || 'Impresion',
              system_service_id: print_service&.system_service_id,
              quantity: line_quantity,
              sale_unit_price_usd: line_unit_usd,
              sale_total_usd: line_total_usd,
              agreed_price_usd: nil,
              has_cost_structure: true,
              cost_status: status_payload[:status],
              cost_status_label: status_payload[:label],
              cost_status_class: status_payload[:css_class],
              pending_cost_usd: status_payload[:pending_usd],
              detail_debt_id: parent_debt&.id,
              search_text: [
                print_label,
                parent_label,
                print_service&.description,
                print_service&.system_service&.name,
                sale.id
              ].join(' ').downcase
            }

            printing_row_key = [
              normalized_pending_cost_lookup_value(parent_label),
              line_quantity.to_d.round(4).to_s('F'),
              line_total_usd.to_d.round(2).to_s('F')
            ].join('|')
            printing_row_key_map[printing_row_key] = true
          end

          next unless line['classification'].to_s == 'nested_expense'

          line_total_usd = line['amount_usd'].to_d.round(2)
          next unless line_total_usd.positive?

          line_quantity = line['quantity'].to_d.round(2)
          line_quantity = 1.to_d unless line_quantity.positive?
          line_unit_usd = (line_total_usd / line_quantity).round(2)

          nested_service = nil
          if line['source_type'].to_s == 'ServiceNestedExpense'
            source_id = line['source_id'].to_i
            nested_service = nested_expense_lookup[source_id]&.nested_service if source_id.positive?
          end

          nested_service_name = nested_service&.description.to_s.strip.presence ||
                                line['source_name'].to_s.strip.presence ||
                                'Servicio anidado'
          debt_line = debt_lines_by_id[line['line_id'].to_s]

          status_payload = pending_cost_status_for_nested_row(
            service: nested_service,
            settlement: settlement,
            debt_line: debt_line,
            line_amount_usd: line_total_usd
          )

          rows << {
            sale_id: sale.id,
            sold_at: sale.created_at,
            nested_sale: true,
            parent_service_name: parent_service_name,
            parent_service_system_name: parent_service&.system_service&.name.to_s.strip.presence,
            service_id: nested_service&.id,
            service_name: nested_service_name,
            service_system_name: nested_service&.system_service&.name.to_s.strip,
            system_service_id: nested_service&.system_service_id,
            quantity: line_quantity,
            sale_unit_price_usd: line_unit_usd,
            sale_total_usd: line_total_usd,
            agreed_price_usd: nested_service&.to_agree? ? line_unit_usd : nil,
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
              sale.id
            ].join(' ').downcase
          }
        end
      end

      sale_printings.each do |printing_row|
        printing_service = services_by_id[printing_row['printing_service_id'].to_i]
        parent_label = printing_row['parent_service_name'].to_s.strip.presence || 'Servicio'
        parent_service = services_by_id[printing_row['service_id'].to_i]
        if parent_service.blank?
          parent_service = resolve_pending_cost_service_for_snapshot(
            service_name: parent_label,
            system_name: nil,
            lookup: service_lookup
          )
        end
        quantity = printing_row['quantity'].to_d.round(2)
        quantity = 1.to_d unless quantity.positive?
        total_usd = printing_row['total_sale_price_usd'].to_d.round(2)
        next unless total_usd.positive?

        dedupe_key = [
          normalized_pending_cost_lookup_value(parent_label),
          quantity.to_d.round(4).to_s('F'),
          total_usd.to_d.round(2).to_s('F')
        ].join('|')
        next if printing_row_key_map[dedupe_key]

        unit_usd = (total_usd / quantity).round(2)
        source_name_raw = printing_row['source_name'].to_s.strip.presence || 'Impresion fisica'
        source_name = pending_cost_child_service_display_name(
          service: printing_service,
          fallback_name: source_name_raw,
          classification: printing_row['classification']
        )

        status_payload = pending_cost_status_metadata('no_cost', pending_usd: 0.to_d, total_usd: total_usd)

        rows << {
          sale_id: sale.id,
          sold_at: sale.created_at,
          nested_sale: false,
          printing_sale: true,
          parent_service_name: parent_label,
          parent_service_system_name: parent_service&.system_service&.name.to_s.strip.presence,
          service_id: printing_service&.id,
          service_name: source_name,
          service_system_name: printing_service&.system_service&.name.to_s.strip.presence || 'Impresion',
          system_service_id: printing_service&.system_service_id,
          quantity: quantity,
          sale_unit_price_usd: unit_usd,
          sale_total_usd: total_usd,
          agreed_price_usd: nil,
          has_cost_structure: false,
          cost_status: status_payload[:status],
          cost_status_label: status_payload[:label],
          cost_status_class: status_payload[:css_class],
          pending_cost_usd: status_payload[:pending_usd],
          detail_debt_id: nil,
          search_text: [
            source_name,
            parent_label,
            'impresion',
            sale.id
          ].join(' ').downcase
        }
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

    Array(parsed_notes['service_cost_settlements']).filter_map do |row|
      next unless row.is_a?(Hash)

      row.deep_stringify_keys
    end
  end

  def pending_cost_printing_sales_for_sale(sale:)
    parsed_notes = begin
      parsed = JSON.parse(sale.notes.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    Array(parsed_notes['sold_service_printings']).filter_map do |row|
      next unless row.is_a?(Hash)

      row.deep_stringify_keys
    end
  end

  def build_pending_cost_service_lookup(service_items:)
    snapshot_name_keys = Array(service_items).filter_map do |item|
      normalized_pending_cost_lookup_value(item&.product_name)
    end.uniq

    by_key = Hash.new { |hash, key| hash[key] = [] }
    by_sale_key = Hash.new { |hash, key| hash[key] = [] }
    by_description = Hash.new { |hash, key| hash[key] = [] }
    sale_name_prefix_entries = []
    printing_sale_name_entries = []

    if snapshot_name_keys.empty?
      return {
        by_key: by_key,
        by_sale_key: by_sale_key,
        by_description: by_description,
        sale_name_prefix_entries: sale_name_prefix_entries,
        printing_sale_name_entries: printing_sale_name_entries,
        services_by_id: {}
      }
    end

    services = current_business
               .services
               .includes(:system_service, :service_expense_structures)
               .to_a

    services.each do |service|
      description_key = normalized_pending_cost_lookup_value(service.description)
      system_key = normalized_pending_cost_lookup_value(service.system_service&.name)
      sale_display_key = normalized_pending_cost_lookup_value(service.print_sale_display_name)

      matches_snapshot = snapshot_name_keys.include?(description_key) ||
                         snapshot_name_keys.any? do |snapshot_key|
                           sale_display_key.present? && snapshot_key.start_with?(sale_display_key)
                         end
      next unless matches_snapshot

      if description_key.present?
        by_key[[description_key, system_key]] << service
        by_description[description_key] << service
      end

      next unless sale_display_key.present?

      by_sale_key[[sale_display_key, system_key]] << service
      by_sale_key[[sale_display_key, nil]] << service
      sale_name_prefix_entries << {
        sale_display_key: sale_display_key,
        system_key: system_key,
        service: service
      }

      next unless service.printing_type_service?

      printing_sale_name_entries << {
        sale_display_key: sale_display_key,
        system_key: system_key,
        service: service
      }
    end

    {
      by_key: by_key,
      by_sale_key: by_sale_key,
      by_description: by_description,
      sale_name_prefix_entries: sale_name_prefix_entries,
      printing_sale_name_entries: printing_sale_name_entries,
      services_by_id: services.index_by(&:id)
    }
  end

  def resolve_pending_cost_service_for_snapshot(service_name:, system_name:, lookup:)
    description_key = normalized_pending_cost_lookup_value(service_name)
    return nil if description_key.blank?

    system_key = normalized_pending_cost_lookup_value(system_name)
    exact_matches = lookup[:by_key][[description_key, system_key]]
    return exact_matches.first if exact_matches.present?

    exact_sale_matches = lookup[:by_sale_key][[description_key, system_key]]
    return exact_sale_matches.first if exact_sale_matches.present?

    if system_key.present?
      generic_prefixed_matches = Array(lookup[:sale_name_prefix_entries]).filter_map do |entry|
        sale_key = entry[:sale_display_key]
        next if sale_key.blank?
        next unless entry[:system_key] == system_key

        entry[:service] if description_key.start_with?(sale_key)
      end

      return generic_prefixed_matches.first if generic_prefixed_matches.size == 1

      prefixed_matches = Array(lookup[:printing_sale_name_entries]).filter_map do |entry|
        sale_key = entry[:sale_display_key]
        next if sale_key.blank?
        next unless entry[:system_key] == system_key

        entry[:service] if description_key.start_with?(sale_key)
      end

      return prefixed_matches.first if prefixed_matches.size == 1
    end

    generic_fallback_prefixed_matches = Array(lookup[:sale_name_prefix_entries]).filter_map do |entry|
      sale_key = entry[:sale_display_key]
      next if sale_key.blank?

      entry[:service] if description_key.start_with?(sale_key)
    end

    return generic_fallback_prefixed_matches.first if generic_fallback_prefixed_matches.size == 1

    fallback_sale_matches = lookup[:by_sale_key][[description_key, nil]]
    return fallback_sale_matches.first if fallback_sale_matches.size == 1

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

  def pending_cost_status_for_direct_row(service:, settlement:, debt:, quantity:)
    if debt.present?
      return pending_cost_status_metadata(
        debt.service_cost_overall_status,
        pending_usd: debt.service_cost_pending_total_usd,
        total_usd: debt.service_cost_total_usd
      )
    end

    settlement_hash = settlement.is_a?(Hash) ? settlement.deep_stringify_keys : {}
    if settlement_hash.present?
      pending_usd = settlement_hash['pending_cost_usd'].to_d.round(2)
      paid_usd = settlement_hash['paid_cost_usd'].to_d.round(2)
      total_usd = settlement_hash['total_cost_usd'].to_d.round(2)

      status = if pending_usd <= 0.01.to_d
                 'paid'
               elsif paid_usd.positive?
                 'partial'
               else
                 'pending'
               end

      return pending_cost_status_metadata(status, pending_usd: pending_usd, total_usd: total_usd)
    end

    if service_has_active_manager_or_variable_structure?(service)
      unit_cost_usd = service.total_expense_usd(active_only: true).to_d.round(2)
      total_cost_usd = (unit_cost_usd * quantity.to_d).round(2)

      return pending_cost_status_metadata(
        'pending',
        pending_usd: total_cost_usd,
        total_usd: total_cost_usd
      )
    end

    pending_cost_status_metadata('no_cost', pending_usd: 0.to_d, total_usd: 0.to_d)
  end

  def service_has_active_manager_or_variable_structure?(service)
    return false if service.blank?

    service.service_expense_structures.any? do |structure|
      next false unless ActiveModel::Type::Boolean.new.cast(structure.active_for_sales)

      structure.service_manager_expenses.exists? || structure.service_variable_expenses.exists?
    end
  end

  def pending_cost_status_for_nested_row(service:, settlement:, debt_line:, line_amount_usd:)
    if service.present? && !service_has_active_cost_structure?(service)
      return pending_cost_status_metadata('no_cost', pending_usd: 0.to_d, total_usd: line_amount_usd)
    end

    if debt_line.present?
      return pending_cost_status_metadata(
        debt_line['status'],
        pending_usd: debt_line['pending_usd'].to_d,
        total_usd: debt_line['amount_usd'].to_d
      )
    end

    settlement_hash = settlement.is_a?(Hash) ? settlement.deep_stringify_keys : {}
    if settlement_hash.blank?
      return pending_cost_status_metadata('no_cost', pending_usd: 0.to_d,
                                                     total_usd: line_amount_usd)
    end

    pending_usd = settlement_hash['pending_cost_usd'].to_d.round(2)
    paid_usd = settlement_hash['paid_cost_usd'].to_d.round(2)

    status = if pending_usd <= 0.01.to_d
               'paid'
             elsif paid_usd.positive?
               'partial'
             else
               'pending'
             end

    approximated_pending_usd = status == 'paid' ? 0.to_d : line_amount_usd.to_d
    pending_cost_status_metadata(status, pending_usd: approximated_pending_usd, total_usd: line_amount_usd)
  end

  def pending_cost_status_for_printing_row(settlement:, debt_line:, line_amount_usd:)
    if debt_line.present?
      return pending_cost_status_metadata(
        debt_line['status'],
        pending_usd: debt_line['pending_usd'].to_d,
        total_usd: debt_line['amount_usd'].to_d
      )
    end

    settlement_hash = settlement.is_a?(Hash) ? settlement.deep_stringify_keys : {}
    if settlement_hash.blank?
      return pending_cost_status_metadata('pending', pending_usd: line_amount_usd.to_d,
                                                     total_usd: line_amount_usd)
    end

    pending_usd = settlement_hash['pending_cost_usd'].to_d.round(2)
    paid_usd = settlement_hash['paid_cost_usd'].to_d.round(2)

    status = if pending_usd <= 0.01.to_d
               'paid'
             elsif paid_usd.positive?
               'partial'
             else
               'pending'
             end

    approximated_pending_usd = status == 'paid' ? 0.to_d : line_amount_usd.to_d
    pending_cost_status_metadata(status, pending_usd: approximated_pending_usd, total_usd: line_amount_usd)
  end

  def pending_cost_status_metadata(status, pending_usd:, total_usd:)
    normalized = status.to_s
    normalized = 'pending' unless %w[pending partial paid no_cost].include?(normalized)

    label = case normalized
            when 'pending'
              'Debe'
            when 'partial'
              'Parcial'
            when 'paid'
              'Pagado'
            else
              'Sin costo'
            end

    css_class = case normalized
                when 'pending'
                  'bg-rose-100 text-rose-700 ring-rose-200'
                when 'partial'
                  'bg-amber-100 text-amber-700 ring-amber-200'
                when 'paid'
                  'bg-emerald-100 text-emerald-700 ring-emerald-200'
                else
                  'bg-slate-100 text-slate-600 ring-slate-200'
                end

    {
      status: normalized,
      label: label,
      css_class: css_class,
      pending_usd: pending_usd.to_d.round(2),
      total_usd: total_usd.to_d.round(2)
    }
  end

  def filter_pending_cost_sold_rows(rows:, filters:)
    filtered_rows = rows

    if filters[:query_text].present?
      query = filters[:query_text].downcase
      filtered_rows = filtered_rows.select { |row| row[:search_text].to_s.include?(query) }
    end

    if filters[:system_service_id].present?
      allowed_service_ids = current_business
                            .services
                            .where(system_service_id: filters[:system_service_id])
                            .pluck(:id)
                            .map(&:to_i)
      filtered_rows = filtered_rows.select do |row|
        allowed_service_ids.include?(row[:service_id].to_i)
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
      .pluck('service_expense_structures.service_id')
      .map(&:to_i)
  end

  def pending_cost_account_movement_method(payment_method)
    return 'mobile_payment' if payment_method.to_s == 'mobile'

    payment_method.to_s
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
    lines = if should_use_live_pending_cost_structure?(debt)
              live_lines = build_live_pending_cost_lines_for(debt: debt)
              if live_lines.present?
                apply_paid_amounts_to_live_pending_cost_lines(
                  live_lines: live_lines,
                  stored_lines: debt.service_cost_lines
                )
              else
                debt.service_cost_lines
              end
            else
              debt.service_cost_lines
            end

    if lines.empty?
      total_usd = debt.amount.to_d.round(2)
      paid_usd = debt.paid_amount.to_d.round(2)
      paid_usd = total_usd if paid_usd > total_usd
      pending_usd = (total_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      lines = [
        {
          'line_id' => "debt-#{debt.id}-general",
          'structure_description' => 'Estructura general',
          'classification' => 'general',
          'classification_label' => 'Costo general',
          'source_name' => debt.service&.description.to_s.presence || debt.display_name,
          'amount_usd' => total_usd.to_f,
          'paid_usd' => paid_usd.to_f,
          'pending_usd' => pending_usd.to_f,
          'status' => if pending_usd <= 0
                        'paid'
                      else
                        (paid_usd.positive? ? 'partial' : 'pending')
                      end,
          'source_updatable' => false
        }
      ]
    end

    lines.map do |raw_line|
      line = raw_line.deep_stringify_keys
      line['classification_label'] =
        line['classification_label'].to_s.presence || pending_cost_classification_label(line['classification'])
      line['structure_description'] = line['structure_description'].to_s.presence || 'Sin estructura'
      line['source_name'] = line['source_name'].to_s.presence || 'Sin detalle'
      line['source_updatable'] = ActiveModel::Type::Boolean.new.cast(line['source_updatable'])
      line['payable_line'] = pending_cost_line_payable?(line)
      line['show_in_breakdown'] = pending_cost_line_visible_in_breakdown?(line)

      unless line['payable_line']
        amount_usd = line['amount_usd'].to_d.round(2)
        line['paid_usd'] = amount_usd.to_f
        line['pending_usd'] = 0.0
        line['status'] = 'paid'
      end

      hydrate_pending_cost_display_amounts!(line: line, debt: debt)
      line
    end
  end

  def pending_cost_line_payable?(line)
    classification = line.to_h.deep_stringify_keys['classification'].to_s
    return false if %w[nested_expense product_expense].include?(classification)

    true
  end

  def pending_cost_line_visible_in_breakdown?(line)
    line_hash = line.to_h.deep_stringify_keys
    return true unless line_hash['classification'].to_s == 'product_expense'

    explicit_flag = line_hash['breakdown_in_invoice']
    return ActiveModel::Type::Boolean.new.cast(explicit_flag) unless explicit_flag.nil?

    return false unless line_hash['source_type'].to_s == 'ServiceProductExpense'

    source_id = line_hash['source_id'].to_i
    return false unless source_id.positive?

    @pending_cost_breakdown_cache ||= {}
    return @pending_cost_breakdown_cache[source_id] if @pending_cost_breakdown_cache.key?(source_id)

    visible = ActiveModel::Type::Boolean.new.cast(
      ServiceProductExpense.where(id: source_id).pick(:breakdown_in_invoice)
    )
    @pending_cost_breakdown_cache[source_id] = visible
    visible
  end

  def should_use_live_pending_cost_structure?(debt)
    return false if debt.blank?
    return false unless debt.service_cost_pending?

    debt.service.present?
  end

  def build_live_pending_cost_lines_for(debt:)
    service = current_business
              .services
              .includes(
                { service_expense_structures: [{ service_manager_expenses: :manager }] },
                { service_expense_structures: :service_variable_expenses },
                { service_expense_structures: { service_nested_expenses: :nested_service } },
                { service_expense_structures: { service_product_expenses: %i[producto product_variation] } }
              )
              .find_by(id: debt.service_id)
    return [] if service.blank?

    details = debt.service_cost_details_hash
    multiplier = details['quantity'].to_d
    multiplier = 1.to_d unless multiplier.positive?

    reference_date = debt&.issued_on
    tasa_dolar = CurrencyConverter.rate_to_ves('USD', on_date: reference_date).to_d
    tasa_dolar = TasaCambio.latest_value('Dolar BCV').to_d unless tasa_dolar.positive?

    unidad_vi = reference_rate_to_bs_on_date(reference: 'Unidad VI', on_date: reference_date).to_d
    unidad_vi = TasaCambio.latest_value('Unidad VI').to_d unless unidad_vi.positive?

    line_sequence = 0
    lines = []

    service.service_expense_structures.where(active_for_sales: true).each do |structure|
      structure_label = structure.description.to_s.strip.presence || "Estructura ##{structure.id}"

      structure.service_manager_expenses.each do |expense|
        amount_usd = (expense.current_amount_usd(tasa_dolar: tasa_dolar).to_d * multiplier).round(2)
        next unless amount_usd.positive?

        reference_unit_amount = expense.amount_reference.to_d.round(2)
        reference_total_amount = (reference_unit_amount * multiplier).round(2)

        line_sequence += 1
        lines << {
          'line_id' => "service-#{service.id}-line-#{line_sequence}",
          'service_id' => service.id,
          'service_name' => service.description.to_s,
          'structure_id' => structure.id,
          'structure_description' => structure_label,
          'classification' => 'manager_expense',
          'classification_label' => 'Gestor',
          'source_type' => 'ServiceManagerExpense',
          'source_id' => expense.id,
          'source_name' => expense.manager&.name.to_s.strip.presence || 'Gestor',
          'quantity' => multiplier.to_f,
          'amount_usd' => amount_usd.to_f,
          'paid_usd' => 0.0,
          'pending_usd' => amount_usd.to_f,
          'status' => 'pending',
          'source_updatable' => true,
          'source_currency_reference' => expense.currency_reference.to_s,
          'source_amount_reference_unit' => reference_unit_amount.to_f,
          'source_amount_reference_total' => reference_total_amount.to_f
        }
      end

      structure.service_variable_expenses.each do |expense|
        amount_usd = (expense.current_amount_usd(tasa_dolar: tasa_dolar).to_d * multiplier).round(2)
        next unless amount_usd.positive?

        reference_unit_amount = expense.amount_reference.to_d.round(2)
        reference_total_amount = (reference_unit_amount * multiplier).round(2)

        line_sequence += 1
        lines << {
          'line_id' => "service-#{service.id}-line-#{line_sequence}",
          'service_id' => service.id,
          'service_name' => service.description.to_s,
          'structure_id' => structure.id,
          'structure_description' => structure_label,
          'classification' => 'variable_expense',
          'classification_label' => 'Gasto variable',
          'source_type' => 'ServiceVariableExpense',
          'source_id' => expense.id,
          'source_name' => expense.description.to_s.strip.presence || 'Gasto variable',
          'quantity' => multiplier.to_f,
          'amount_usd' => amount_usd.to_f,
          'paid_usd' => 0.0,
          'pending_usd' => amount_usd.to_f,
          'status' => 'pending',
          'source_updatable' => true,
          'source_currency_reference' => expense.currency_reference.to_s,
          'source_amount_reference_unit' => reference_unit_amount.to_f,
          'source_amount_reference_total' => reference_total_amount.to_f
        }
      end

      structure.service_nested_expenses.each do |expense|
        amount_usd = (expense.total_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d * multiplier).round(2)
        next unless amount_usd.positive?

        nested_service = expense.nested_service
        nested_service_base_reference = nested_service&.currency_base_price.to_s.strip
        nested_service_bs_like_base = [Service::BOLIVAR_REFERENCE, 'Unidad VI'].include?(nested_service_base_reference)

        reference_currency = if nested_service_bs_like_base
                               Service::BOLIVAR_REFERENCE
                             else
                               expense.currency_reference.to_s
                             end

        reference_unit_amount = expense.amount_reference.to_d.round(2)
        reference_total_amount = (reference_unit_amount * multiplier).round(2)

        if nested_service_bs_like_base
          bs_total = (expense.total_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d * multiplier).round(2)

          if bs_total.positive?
            reference_total_amount = bs_total
            reference_unit_amount = (reference_total_amount / multiplier).round(2)
          end
        end

        nested_name = nested_service&.description.to_s.strip.presence || 'Servicio anidado'

        line_sequence += 1
        lines << {
          'line_id' => "service-#{service.id}-line-#{line_sequence}",
          'service_id' => service.id,
          'service_name' => service.description.to_s,
          'structure_id' => structure.id,
          'structure_description' => structure_label,
          'classification' => 'nested_expense',
          'classification_label' => 'Servicio anidado',
          'source_type' => 'ServiceNestedExpense',
          'source_id' => expense.id,
          'source_name' => nested_name,
          'quantity' => (expense.quantity.to_d * multiplier).to_f,
          'amount_usd' => amount_usd.to_f,
          'paid_usd' => 0.0,
          'pending_usd' => amount_usd.to_f,
          'status' => 'pending',
          'source_updatable' => false,
          'source_currency_reference' => reference_currency,
          'source_amount_reference_unit' => reference_unit_amount.to_f,
          'source_amount_reference_total' => reference_total_amount.to_f
        }
      end

      structure.service_product_expenses.each do |expense|
        amount_usd = (expense.total_usd.to_d * multiplier).round(2)
        next unless amount_usd.positive?

        line_sequence += 1
        product_name = expense.producto&.descripcion.to_s.strip.presence || 'Producto'
        variation_name = expense.product_variation&.description.to_s.strip.presence

        lines << {
          'line_id' => "service-#{service.id}-line-#{line_sequence}",
          'service_id' => service.id,
          'service_name' => service.description.to_s,
          'structure_id' => structure.id,
          'structure_description' => structure_label,
          'classification' => 'product_expense',
          'classification_label' => 'Consumible',
          'source_type' => 'ServiceProductExpense',
          'source_id' => expense.id,
          'source_name' => variation_name.present? ? "#{product_name} (#{variation_name})" : product_name,
          'quantity' => (expense.quantity.to_d * multiplier).to_f,
          'amount_usd' => amount_usd.to_f,
          'paid_usd' => 0.0,
          'pending_usd' => amount_usd.to_f,
          'status' => 'pending',
          'source_updatable' => false,
          'source_currency_reference' => nil,
          'breakdown_in_invoice' => expense.breakdown_in_invoice?
        }
      end
    end

    lines
  end

  def apply_paid_amounts_to_live_pending_cost_lines(live_lines:, stored_lines:)
    lines_by_source = Array(stored_lines).each_with_object({}) do |raw_line, hash|
      line = raw_line.deep_stringify_keys
      key = pending_cost_live_line_key(line)
      next if key.blank?

      hash[key] ||= []
      hash[key] << line
    end

    Array(live_lines).map do |raw_line|
      line = raw_line.deep_stringify_keys
      key = pending_cost_live_line_key(line)
      stored_line = key.present? ? lines_by_source[key]&.shift : nil

      amount_usd = line['amount_usd'].to_d.round(2)
      paid_usd = stored_line.to_h['paid_usd'].to_d.round(2)
      paid_usd = amount_usd if paid_usd > amount_usd

      pending_usd = (amount_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      line['paid_usd'] = paid_usd.to_f
      line['pending_usd'] = pending_usd.to_f
      line['status'] = if pending_usd <= 0
                         'paid'
                       elsif paid_usd.positive?
                         'partial'
                       else
                         'pending'
                       end

      line
    end
  end

  def pending_cost_live_line_key(line)
    source_type = line['source_type'].to_s
    source_id = line['source_id'].to_s
    return '' if source_type.blank? || source_id.blank?

    "#{source_type}:#{source_id}"
  end

  def hydrate_pending_cost_display_amounts!(line:, debt:)
    snapshot = resolve_source_reference_snapshot(line)
    reference = snapshot[:reference].to_s.strip
    return if reference.blank?

    amount_usd = line['amount_usd'].to_d.round(2)
    paid_usd = line['paid_usd'].to_d.round(2)
    pending_usd = line['pending_usd'].to_d.round(2)

    configured_total_reference = snapshot[:amount_reference_total].to_d.round(2)
    total_reference = if configured_total_reference.positive?
                        configured_total_reference
                      else
                        convert_usd_to_reference_amount(
                          amount_usd: amount_usd,
                          reference: reference,
                          on_date: debt&.issued_on
                        ).to_d.round(2)
                      end

    paid_reference = convert_usd_to_reference_amount(
      amount_usd: paid_usd,
      reference: reference,
      on_date: debt&.issued_on
    ).to_d.round(2)
    reference_currency = pending_cost_reference_currency(reference)
    line_paid = line['status'].to_s == 'paid' || pending_usd <= 0.01.to_d

    paid_reference = total_reference if reference_currency == 'VES' && line_paid && total_reference.positive?

    pending_reference = if reference_currency == 'VES' && total_reference.positive?
                          computed_pending = (total_reference - paid_reference).round(2)
                          computed_pending.negative? ? 0.to_d : computed_pending
                        else
                          convert_usd_to_reference_amount(
                            amount_usd: pending_usd,
                            reference: reference,
                            on_date: debt&.issued_on
                          ).to_d.round(2)
                        end

    line['source_currency_reference'] = reference
    line['display_currency_reference'] = reference
    line['display_currency_symbol'] = pending_cost_reference_symbol(reference)
    line['display_amount_reference_unit'] = snapshot[:amount_reference_unit].to_d.round(2).to_f
    line['display_amount_reference_total'] = total_reference.to_f
    line['display_paid_reference_total'] = paid_reference.to_f
    line['display_pending_reference_total'] = pending_reference.to_f
    line['display_secondary_currency'] = debt&.currency.to_s.upcase.presence || 'USD'
    line['display_secondary_label'] = pending_cost_secondary_label_for(line['display_secondary_currency'])
    line['display_secondary_symbol'] = pending_cost_secondary_symbol_for(line['display_secondary_currency'])
    line['display_secondary_total'] = amount_usd.to_f
    line['display_secondary_paid'] = paid_usd.to_f
    line['display_secondary_pending'] = pending_usd.to_f
  end

  def resolve_source_reference_snapshot(line)
    line_hash = line.deep_stringify_keys
    reference = line_hash['source_currency_reference'].to_s.strip
    quantity = line_hash['quantity'].to_d
    quantity = 1.to_d unless quantity.positive?

    unit_reference = line_hash['source_amount_reference_unit'].to_d.round(2)
    total_reference = line_hash['source_amount_reference_total'].to_d.round(2)

    if total_reference.positive? || unit_reference.positive?
      total_reference = (unit_reference * quantity).round(2) if total_reference <= 0 && unit_reference.positive?

      return {
        reference: reference,
        amount_reference_unit: unit_reference,
        amount_reference_total: total_reference
      }
    end

    source_type = line_hash['source_type'].to_s
    source_id = line_hash['source_id']

    source_class = {
      'ServiceManagerExpense' => ServiceManagerExpense,
      'ServiceVariableExpense' => ServiceVariableExpense,
      'ServiceNestedExpense' => ServiceNestedExpense
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
      amount_reference_total: source_total_reference
    }
  end

  def pending_cost_reference_symbol(reference)
    normalized = reference.to_s.strip
    return 'Bs' if normalized == 'Bs'
    return '$' if %w[Dolar BCV USD $].include?(normalized)

    TasaCambio.latest_for(normalized)&.symbol.to_s.presence || normalized
  end

  def pending_cost_expected_account_currency_for(line:, debt_currency:)
    reference = line['source_currency_reference'].to_s.strip
    reference = line['display_currency_reference'].to_s.strip if reference.blank?

    reference_currency = pending_cost_reference_currency(reference)
    return 'USDT' if reference_currency == 'USDT'
    return 'VES' if %w[VES USD EUR].include?(reference_currency)

    normalized_debt_currency = debt_currency.to_s.strip.upcase
    return normalized_debt_currency if normalized_debt_currency.present?

    nil
  end

  def pending_cost_expected_account_currency_label(currency)
    case currency.to_s.upcase
    when 'VES'
      'Bs'
    when 'USDT'
      'USDT'
    else
      currency.to_s.upcase
    end
  end

  def build_pending_cost_currency_rates(rows:, accounts:)
    candidate_currencies = []

    Array(rows).each do |row|
      candidate_currencies << row[:debt_currency]
      Array(row[:lines]).each do |line|
        candidate_currencies << line['debt_currency']
      end
    end

    Array(accounts).each do |account|
      candidate_currencies << account.currency
    end

    normalized = candidate_currencies
                 .map { |value| value.to_s.strip.upcase }
                 .select(&:present?)
                 .uniq

    rates = { 'VES' => 1.0 }

    normalized.each do |currency|
      next if rates.key?(currency)

      rates[currency] = CurrencyConverter.rate_to_ves(currency, on_date: Date.current).to_d.to_f
    end

    rates
  end

  def pending_cost_redirect_path(debt:)
    return pending_costs_services_path unless params[:redirect_to_detail].to_s == '1'
    return pending_costs_services_path if debt.blank?

    pending_cost_detail_services_path(debt_id: debt.id)
  end

  def apply_pending_cost_detail_display_amounts!(lines:, debt:, payments_by_line:)
    Array(lines).each do |line|
      payments = Array(payments_by_line.to_h[line['line_id'].to_s])
      apply_pending_cost_payment_history_display!(line: line, debt: debt, payments: payments)
    end
  end

  def pending_cost_debt_payments_by_line(debt:)
    debt.debt_payments
        .sort_by do |payment|
          [
            payment.occurred_at || Date.new(1970, 1, 1),
            payment.created_at || Time.zone.at(0),
            payment.id.to_i
          ]
        end
        .reverse_each
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |payment, grouped|
      line_id = pending_cost_line_id_from_payment_notes(payment.notes)
      next if line_id.blank?

      grouped[line_id] << payment
    end
  end

  def pending_cost_line_id_from_payment_notes(notes)
    notes.to_s[/\[LINE:([^\]]+)\]/, 1].to_s.strip
  end

  def pending_cost_account_movements_for_payment(payment:, debt:, line:)
    token = "[DP:#{payment.id}]"
    scope = AccountMovement
            .joins(:account)
            .where(accounts: { business_id: current_business.id })

    tagged_movements = scope.where('account_movements.description ILIKE ?', "%#{token}%").to_a
    return tagged_movements if tagged_movements.any?

    legacy_descriptions = pending_cost_legacy_movement_descriptions(payment: payment, debt: debt, line: line)
    return [] if legacy_descriptions.empty?

    scope
      .where(account_id: payment.account_id)
      .where(amount: payment.amount)
      .where('DATE(account_movements.occurred_at) = ?', payment.occurred_at)
      .where(description: legacy_descriptions)
      .to_a
  end

  def pending_cost_legacy_movement_descriptions(payment:, debt:, line:)
    service_name = debt.service_cost_details_hash['service_name'].to_s.strip.presence ||
                   debt.service&.description.to_s.strip.presence ||
                   'Servicio'

    source_name = line['source_name'].to_s.strip.presence || 'clasificacion'

    base = case line['classification'].to_s
           when 'manager_expense'
             "Pago #{source_name} por servicio #{service_name}"
           when 'variable_expense'
             "Pago de #{source_name} por servicio de #{service_name}"
           else
             "Pago de costo por servicio #{service_name}"
           end

    descriptions = [base]
    descriptions << "#{base} - Ref #{payment.reference}" if payment.reference.to_s.strip.present?

    descriptions.uniq
  end

  def pending_cost_status_from_lines(lines)
    pending_usd = Array(lines).sum { |line| line['pending_usd'].to_d }.round(2)
    paid_usd = Array(lines).sum { |line| line['paid_usd'].to_d }.round(2)

    return 'paid' if pending_usd <= 0.01.to_d
    return 'partial' if paid_usd.positive?

    'pending'
  end

  def apply_pending_cost_payment_history_display!(line:, debt:, payments:)
    reference = line['display_currency_reference'].to_s.strip
    reference_currency = pending_cost_reference_currency(reference)
    return unless %w[USD EUR].include?(reference_currency)

    total_reference = line['display_amount_reference_total'].to_d.round(2)
    return unless total_reference.positive?

    paid_reference = Array(payments).sum do |payment|
      convert_paid_amount_to_reference_amount(
        amount: payment.amount,
        from_currency: payment.currency,
        reference: reference,
        on_date: payment.occurred_at
      )
    end.round(2)

    paid_reference = total_reference if paid_reference > total_reference
    pending_reference = (total_reference - paid_reference).round(2)
    pending_reference = 0.to_d if pending_reference.abs <= 0.01.to_d

    bs_rate = reference_rate_to_bs_on_date(reference: reference, on_date: debt&.issued_on)
    return unless bs_rate.positive?

    line['display_paid_reference_total'] = paid_reference.to_f
    line['display_pending_reference_total'] = pending_reference.to_f
    line['display_secondary_currency'] = 'VES'
    line['display_secondary_label'] = pending_cost_secondary_label_for('VES')
    line['display_secondary_symbol'] = pending_cost_secondary_symbol_for('VES')
    line['display_secondary_total'] = (total_reference * bs_rate).round(2).to_f
    line['display_secondary_paid'] = (paid_reference * bs_rate).round(2).to_f
    line['display_secondary_pending'] = (pending_reference * bs_rate).round(2).to_f
  end

  def pending_cost_secondary_symbol_for(currency)
    normalized_currency = currency.to_s.upcase
    Account::CURRENCIES.dig(normalized_currency, :symbol) || normalized_currency
  end

  def pending_cost_secondary_label_for(currency)
    normalized_currency = currency.to_s.upcase
    return 'Bs' if normalized_currency == 'VES'

    normalized_currency
  end

  def pending_cost_classification_label(classification)
    case classification.to_s
    when 'manager_expense'
      'Gestor'
    when 'variable_expense'
      'Gasto variable'
    when 'nested_expense'
      'Servicio anidado'
    when 'product_expense'
      'Consumible'
    when 'printing_expense'
      'Impresion fisica'
    when 'adjustment'
      'Ajuste'
    else
      'Costo general'
    end
  end

  def pending_cost_child_service_display_name(service:, fallback_name:, classification: nil)
    fallback = fallback_name.to_s.strip.presence || 'Servicio'
    return fallback if service.blank?

    is_lamination_child = service.respond_to?(:lamination_type_service?) && service.lamination_type_service?
    is_lamination_child ||= classification.to_s == 'lamination_service'
    return fallback unless is_lamination_child

    service.print_sale_display_name.to_s.strip.presence || service.description.to_s.strip.presence || fallback
  end

  def parse_pending_cost_decimal(value)
    return 0.to_d if value.blank?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip
                   .gsub(/\s/, '')
                   .gsub(/[^\d.,-]/, '')

    normalized = if cleaned.include?(',')
                   cleaned.gsub('.', '').gsub(',', '.')
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
    return Date.strptime(raw, '%d-%m-%Y') if raw.match?(/\A\d{2}-\d{2}-\d{4}\z/)

    Date.iso8601(raw)
  rescue ArgumentError
    nil
  end

  def pending_cost_movement_occurred_at(payment_date)
    venezuela_now = Time.current.in_time_zone('America/Caracas')

    ActiveSupport::TimeZone['America/Caracas'].local(
      payment_date.year,
      payment_date.month,
      payment_date.day,
      venezuela_now.hour,
      venezuela_now.min,
      venezuela_now.sec
    )
  end

  def lock_paid_pending_cost_line_snapshot!(line:, paid_amount_original:, paid_currency:, on_date:)
    return unless line['status'].to_s == 'paid'

    snapshot = resolve_source_reference_snapshot(line)
    reference = snapshot[:reference].to_s.strip
    return if reference.blank?

    quantity = line['quantity'].to_d
    quantity = 1.to_d unless quantity.positive?

    unit_reference = line['source_amount_reference_unit'].to_d.round(2)
    total_reference = line['source_amount_reference_total'].to_d.round(2)

    if total_reference <= 0 || unit_reference <= 0
      total_reference = convert_paid_amount_to_reference_amount(
        amount: paid_amount_original,
        from_currency: paid_currency,
        reference: reference,
        on_date: on_date
      )

      if total_reference <= 0
        total_reference = convert_usd_to_reference_amount(
          amount_usd: line['amount_usd'].to_d,
          reference: reference,
          on_date: on_date
        )
      end

      if total_reference.positive?
        total_reference = total_reference.round(2)
        unit_reference = (total_reference / quantity).round(2)
      end
    end

    line['source_currency_reference'] = reference
    line['source_amount_reference_unit'] = unit_reference.to_f if unit_reference.positive?
    line['source_amount_reference_total'] = total_reference.to_f if total_reference.positive?
  end

  def sync_paid_service_cost_snapshot_to_sale!(debt:, details:)
    sale = debt.venta
    return if sale.blank?

    notes_payload = parse_pending_cost_sale_notes(sale.notes)
    settlements = Array(notes_payload['service_cost_settlements']).filter_map do |row|
      next unless row.is_a?(Hash)

      row.deep_stringify_keys
    end

    normalized_lines = normalize_pending_cost_lines_for_sale_notes(details['lines'])
    total_usd = details['total_usd'].to_d.round(2)
    paid_usd = details['paid_usd'].to_d.round(2)
    pending_usd = details['pending_usd'].to_d.round(2)

    service_id = details['service_id'].to_i
    service_id = debt.service_id.to_i if service_id <= 0 && debt.service_id.present?

    service_name = details['service_name'].to_s.strip
    service_name = debt.service&.description.to_s.strip if service_name.blank?
    service_name = debt.display_name.to_s.strip if service_name.blank?

    settlement = (settlements.find { |row| row['service_id'].to_i == service_id } if service_id.positive?)
    settlement ||= settlements.find do |row|
      row['service_name'].to_s.strip.casecmp?(service_name)
    end

    quantity = settlement&.dig('quantity').to_d
    if quantity <= 0
      quantity = normalized_lines.sum { |line| line['quantity'].to_d }.round(2)
      quantity = 1.to_d unless quantity.positive?
    end

    snapshot = {
      'service_name' => service_name,
      'quantity' => quantity.to_f,
      'unit_cost_usd' => (total_usd / quantity).round(2).to_f,
      'total_cost_usd' => total_usd.to_f,
      'paid_cost_usd' => paid_usd.to_f,
      'pending_cost_usd' => pending_usd.to_f,
      'detail_lines' => normalized_lines
    }
    snapshot['service_id'] = service_id if service_id.positive?

    if settlement.present?
      settlement.merge!(snapshot)
    else
      settlements << snapshot
    end

    notes_payload['service_cost_settlements'] = settlements
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
      amount_usd = line['amount_usd'].to_d.round(2)
      paid_usd = line['paid_usd'].to_d.round(2)
      paid_usd = amount_usd if paid_usd > amount_usd

      pending_usd = (amount_usd - paid_usd).round(2)
      pending_usd = 0.to_d if pending_usd.abs <= 0.01.to_d

      status = if pending_usd <= 0
                 'paid'
               elsif paid_usd.positive?
                 'partial'
               else
                 'pending'
               end

      line.merge(
        'amount_usd' => amount_usd.to_f,
        'paid_usd' => paid_usd.to_f,
        'pending_usd' => pending_usd.to_f,
        'status' => status
      )
    end
  end

  def apply_pending_cost_source_snapshot!(line:, snapshot:, debt:)
    return if snapshot.blank?

    line['source_currency_reference'] = snapshot[:reference].to_s
    line['source_amount_reference_unit'] = snapshot[:amount_reference_unit].to_d.round(2).to_f
    line['source_amount_reference_total'] = snapshot[:amount_reference_total].to_d.round(2).to_f

    hydrate_pending_cost_display_amounts!(line: line, debt: debt)
  end

  def update_pending_cost_source_row!(line:, amount_usd:, paid_amount_original:, paid_currency:, on_date:)
    return unless ActiveModel::Type::Boolean.new.cast(line['source_updatable'])

    source_type = line['source_type'].to_s
    source_id = line['source_id']
    return if source_id.blank?

    source_class = {
      'ServiceManagerExpense' => ServiceManagerExpense,
      'ServiceVariableExpense' => ServiceVariableExpense
    }[source_type]
    return unless source_class

    source_row = source_class.find_by(id: source_id)
    return unless source_row

    reference = line['source_currency_reference'].to_s.strip.presence || source_row.currency_reference.to_s
    reference = 'Dolar BCV' if reference.blank?

    reference_amount = convert_paid_amount_to_reference_amount(
      amount: paid_amount_original,
      from_currency: paid_currency,
      reference: reference,
      on_date: on_date
    )

    if reference_amount.to_d <= 0
      reference_amount = convert_usd_to_reference_amount(
        amount_usd: amount_usd,
        reference: reference,
        on_date: on_date
      )
    end

    return unless reference_amount.to_d.positive?

    source_row.update!(
      currency_reference: reference,
      amount_reference: reference_amount.to_d.round(2)
    )

    {
      reference: source_row.currency_reference.to_s.strip.presence || reference,
      amount_reference_unit: source_row.amount_reference.to_d.round(2),
      amount_reference_total: source_row.amount_reference.to_d.round(2)
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
      on_date: on_date
    )

    conversion&.dig(:amount).to_d.round(2)
  end

  def pending_cost_reference_currency(reference)
    normalized = reference.to_s.strip.upcase
    return '' if normalized.blank?

    return 'USDT' if normalized.include?('USDT')
    return 'VES' if %w[BS VES BOLIVAR BOLIVARES].include?(normalized)
    return 'USD' if normalized == '$' || normalized.include?('DOLAR') || normalized.include?('USD')
    return 'EUR' if normalized == '€' || normalized.include?('EURO') || normalized.include?('EUR')
    return normalized if Account::CURRENCIES.key?(normalized)

    ''
  end

  def convert_usd_to_reference_amount(amount_usd:, reference:, on_date:)
    usd_value = amount_usd.to_d
    return 0.to_d unless usd_value.positive?

    normalized_reference = reference.to_s.strip
    return usd_value.round(2) if normalized_reference.blank? || %w[Dolar BCV $ USD].include?(normalized_reference)

    usd_to_bs = CurrencyConverter.convert(
      amount: usd_value,
      from_currency: 'USD',
      to_currency: 'VES',
      on_date: on_date
    )&.dig(:amount).to_d
    return 0.to_d unless usd_to_bs.positive?

    return usd_to_bs.round(2) if normalized_reference == 'Bs'

    reference_rate_bs = reference_rate_to_bs_on_date(reference: normalized_reference, on_date: on_date)
    return 0.to_d unless reference_rate_bs.positive?

    (usd_to_bs / reference_rate_bs).round(2)
  end

  def reference_rate_to_bs_on_date(reference:, on_date:)
    scope = TasaCambio.where(description: reference)
    return 0.to_d if scope.blank?

    if on_date.present?
      historical_rate = scope
                        .where('fecha_referencia <= ?', on_date)
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
        value: 'Bs',
        label: 'Bolivar',
        symbol: 'Bs',
        rate_bs: 1.to_d
      }
    ]

    latest_rates.each do |rate|
      next if !include_unidad_vi && rate.description == 'Unidad VI'

      rows << {
        value: rate.description,
        label: rate.description,
        symbol: rate.symbol.presence || TasaCambio::DEFAULT_SYMBOLS[rate.description] || rate.description,
        rate_bs: rate.valor.to_d
      }
    end

    rows
  end

  def render_show_blocked(message)
    respond_to do |format|
      format.html do
        render partial: 'services/show_blocked',
               locals: { message: message },
               status: :forbidden
      end
    end
  end
end
