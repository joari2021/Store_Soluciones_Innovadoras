class SystemServicesController < ApplicationController
  before_action :set_system_service, only: %i[edit update destroy]
  
  def index
    @system_services = SystemService.order(name: :asc)
  end

  def new
    @system_service = SystemService.new
  end

  def create
    @system_service = SystemService.new(system_service_params)
    if @system_service.save
      redirect_to system_services_path, notice: "System Service created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @system_service.update(system_service_params)
      redirect_to system_services_path, notice: "Sistema de servicios actualizado exitosamente."
    else
      render :edit
    end
  end

  def destroy
    @system_service.destroy
    redirect_to system_services_path, notice: "Sistema de servicios eliminado exitosamente."
  end

  private

  def set_system_service
    @system_service = SystemService.find(params[:id])
  end

  def system_service_params
    params.require(:system_service).permit(
      :name,
      :image
    )
  end
end