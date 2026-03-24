class ServicesController < ApplicationController
  before_action :set_service, only: %i[edit update destroy]

  def index
    if params[:query_text].present?
      @services = Service.joins(:system_service).whose_name_starts_with(params[:query_text])
    else
      @services = Service.includes(:system_service).order('system_services.name ASC, services.description ASC')
    end

    @pagy, @services = pagy_countless(@services, items: 24)
  end

  def new
    @service = Service.new
    @service.service_managers.build
    @managers = Manager.all.order(:name)
  end

  def create
    @service = Service.new(service_params)
    if @service.save
      redirect_to services_path, notice: "Servicio creado exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @service = Service.find(params[:id])
    respond_to do |format|
      format.html { render partial: "services/show", locals: { service: @service } }
    end
  end

  def export_excel
    services = Service
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
    @service.service_managers.build if @service.service_managers.empty? # Asegura que haya al menos un ServiceManager para renderizar
    @managers = Manager.all.order(:name)
  end

  def update
    if @service.update(service_params)
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
    @service = Service.find(params[:id])
  end

  def service_params
    params.require(:service).permit(
    :description, 
    :sale_price, 
    :currency_base_price, 
    :value_units, 
    :cost, 
    :system_service_id, 
    :physical_requirements,
    :digital_requirements,
    :required_data,
    :personal_steps,
    :note,
    :delivery_content,
    :delivery_time,
    :available,
    service_managers_attributes: [:id, :manager_id, :cost, :reference_cost, :_destroy])
  end
 
end
