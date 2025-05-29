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
    service_managers_attributes: [:id, :manager_id, :cost, :_destroy])
  end
 
end
