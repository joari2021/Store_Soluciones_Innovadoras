class ServicesController < ApplicationController
  before_action :set_service, only: %i[show edit update destroy]
  before_action :set_form_collections, only: %i[new create edit update]

  def index
    @services = if params[:query_text].present?
                  Service
                    .includes(:system_service, service_expense_structures: %i[
                      service_variable_expenses
                    ] + [
                      { service_manager_expenses: :manager },
                      { service_nested_expenses: :nested_service },
                      { service_product_expenses: :producto }
                    ])
                    .joins(:system_service)
                    .whose_name_starts_with(params[:query_text])
                else
                  Service
                    .includes(:system_service, service_expense_structures: %i[
                      service_variable_expenses
                    ] + [
                      { service_manager_expenses: :manager },
                      { service_nested_expenses: :nested_service },
                      { service_product_expenses: :producto }
                    ])
                    .order('system_services.name ASC, services.description ASC')
                end

    @pagy, @services = pagy_countless(@services, items: 24)
  end

  def new
    @service = Service.new(pricing_mode: :fixed, currency_base_price: 'Dolar BCV')
  end

  def create
    @service = Service.new(service_params)

    if @service.save
      redirect_to services_path, notice: 'Servicio creado exitosamente.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
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
    @service = Service
               .includes(:system_service, service_expense_structures: %i[
                 service_variable_expenses
               ] + [
                 { service_manager_expenses: :manager },
                 { service_nested_expenses: :nested_service },
                 { service_product_expenses: :producto }
               ])
               .find(params[:id])
  end

  def set_form_collections
    @managers = Manager.order(:name)
    @products_for_expenses = if current_business.present?
                               current_business.productos.order(:descripcion)
                             else
                               Producto.none
                             end

    scope = Service.includes(:system_service).where(nested_available: true).order(:description)
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
        { service_product_expenses_attributes: %i[id producto_id quantity _destroy] }
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
end
