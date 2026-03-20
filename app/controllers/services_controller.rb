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
                        { service_product_expenses: [:product_variation, { producto: :product_variations }] }
                      ])
    scoped_services = scoped_services.visible_for_user(Current.user)

    @services = if params[:query_text].present?
                  scoped_services
                    .joins(:system_service)
                    .whose_name_starts_with(params[:query_text])
                else
                  scoped_services
                    .order('system_services.name ASC, services.description ASC')
                end

    @pagy, @services = pagy_countless(@services, items: 24)
  end

  def pending_costs
    scope = current_business
            .debts
            .includes(:service, :venta, :debt_payments)
            .where(debt_kind: 'payable', service_cost_pending: true)
            .order(created_at: :desc)

    @pending_cost_rows = scope.filter_map do |debt|
      lines = normalized_pending_cost_lines_for(debt)
      next if lines.empty?

      pending_usd = lines.sum { |line| line['pending_usd'].to_d }.round(2)
      next unless pending_usd.positive?

      paid_usd = lines.sum { |line| line['paid_usd'].to_d }.round(2)
      total_usd = lines.sum { |line| line['amount_usd'].to_d }.round(2)

      {
        debt: debt,
        lines: lines,
        debt_currency: debt.currency.to_s.upcase,
        total_usd: total_usd,
        paid_usd: paid_usd,
        pending_usd: pending_usd,
        status: pending_cost_status_from_lines(lines)
      }
    end

    @pending_cost_count = @pending_cost_rows.sum do |row|
      row[:lines].count do |line|
        line['pending_usd'].to_d.positive?
      end
    end
    @pending_cost_total = @pending_cost_rows.sum { |row| row[:pending_usd].to_d }.round(2)
    @pending_cost_currency_rates = build_pending_cost_currency_rates(rows: @pending_cost_rows,
                                                                     accounts: @pending_cost_accounts)
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

    pending_usd = lines.sum { |line| line['pending_usd'].to_d }.round(2)
    paid_usd = lines.sum { |line| line['paid_usd'].to_d }.round(2)
    total_usd = lines.sum { |line| line['amount_usd'].to_d }.round(2)

    @pending_cost_row = {
      debt: debt,
      lines: lines,
      debt_currency: debt.currency.to_s.upcase,
      total_usd: total_usd,
      paid_usd: paid_usd,
      pending_usd: pending_usd,
      status: pending_cost_status_from_lines(lines)
    }

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

      unless /^\d{6}$/.match?(reference)
        return redirect_to redirect_path,
                           alert: 'La referencia bancaria debe tener exactamente 6 digitos.'
      end
    else
      payment_method = nil
      reference = nil
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
    if amount_in_debt_currency > pending_line_usd + 0.01.to_d
      return redirect_to redirect_path,
                         alert: 'El pago excede el saldo pendiente de la clasificacion seleccionada.'
    end

    update_source_cost = ActiveModel::Type::Boolean.new.cast(params[:update_source_cost])

    Debt.transaction do
      debt.debt_payments.create!(
        account: account,
        amount: amount_original,
        currency: account.currency,
        payment_method: payment_method,
        reference: reference,
        occurred_at: payment_date,
        notes: "Pago costo servicio [DEBT:#{debt.id}] [LINE:#{line_id}]"
      )

      line['paid_usd'] = (line['paid_usd'].to_d + amount_in_debt_currency).round(2).to_f
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
        update_pending_cost_source_row!(line: line, amount_usd: amount_in_debt_currency,
                                        on_date: payment_date)
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
    end

    redirect_to pending_cost_redirect_path(debt: debt),
                notice: 'Pago registrado en la linea de costo seleccionada.'
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
        raw_service: params[:service]
      )

      unless references_synced
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

  def set_service
    @service = current_business
               .services
               .includes(:system_service, service_expense_structures: %i[
                 service_variable_expenses
               ] + [
                 { service_manager_expenses: :manager },
                 { service_nested_expenses: :nested_service },
                 { service_product_expenses: [:product_variation, { producto: :product_variations }] }
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
    @service_expenses_bcv_rate = rate.positive? ? rate : TasaCambio.latest_value('Dolar BCV').to_d

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
        :_destroy,
        { service_manager_expenses_attributes: %i[id manager_id currency_reference amount_reference amount_usd
                                                  amount_bs _destroy] },
        { service_variable_expenses_attributes: %i[id description currency_reference amount_reference amount_usd
                                                   amount_bs _destroy] },
        { service_nested_expenses_attributes: %i[id nested_service_id quantity currency_reference amount_reference
                                                 _destroy] },
        { service_product_expenses_attributes: %i[id producto_id product_variation_id quantity _destroy] }
      ]
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
      nested_key: :service_manager_expenses_attributes
    )

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_variable_expenses_attributes
    )

    merge_nested_reference_fields!(
      permitted_structures: permitted_structures,
      raw_structures: raw_structures,
      nested_key: :service_nested_expenses_attributes
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

      success &&= sync_nested_expense_reference_rows!(
        scope: structure.service_nested_expenses,
        raw_rows: raw_structure[:service_nested_expenses_attributes] || raw_structure['service_nested_expenses_attributes']
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

  def set_pending_cost_accounts
    @pending_cost_accounts = current_business.accounts.where(active: true).order(:currency, :name)
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
      hydrate_pending_cost_display_amounts!(line: line, debt: debt)
      line
    end
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
    pending_reference = convert_usd_to_reference_amount(
      amount_usd: pending_usd,
      reference: reference,
      on_date: debt&.issued_on
    ).to_d.round(2)

    line['source_currency_reference'] = reference
    line['display_currency_reference'] = reference
    line['display_currency_symbol'] = pending_cost_reference_symbol(reference)
    line['display_amount_reference_unit'] = snapshot[:amount_reference_unit].to_d.round(2).to_f
    line['display_amount_reference_total'] = total_reference.to_f
    line['display_paid_reference_total'] = paid_reference.to_f
    line['display_pending_reference_total'] = pending_reference.to_f
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

  def pending_cost_status_from_lines(lines)
    pending_usd = Array(lines).sum { |line| line['pending_usd'].to_d }.round(2)
    paid_usd = Array(lines).sum { |line| line['paid_usd'].to_d }.round(2)

    return 'paid' if pending_usd <= 0.01.to_d
    return 'partial' if paid_usd.positive?

    'pending'
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
    when 'adjustment'
      'Ajuste'
    else
      'Costo general'
    end
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

  def update_pending_cost_source_row!(line:, amount_usd:, on_date:)
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

    reference_amount = convert_usd_to_reference_amount(amount_usd: amount_usd, reference: reference, on_date: on_date)
    return unless reference_amount.to_d.positive?

    source_row.update!(
      currency_reference: reference,
      amount_reference: reference_amount.to_d.round(2)
    )
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
