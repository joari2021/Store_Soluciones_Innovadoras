class ServicesController < ApplicationController
  before_action :set_service, only: %i[edit update destroy]

  def index
    @services = Service.includes(:system_service).order('system_services.name ASC, services.description ASC')

    if params[:query_text].present?
      @services = @services.whose_name_starts_with(params[:query_text])
    end
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
    params.require(:service).permit(:description, :sale_price, :currency_base_price, :value_units, :cost, :system_service_id, service_managers_attributes: [:id, :manager_id, :cost, :reference_cost, :_destroy])
  end
 
end
