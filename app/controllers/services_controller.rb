class ServicesController < ApplicationController
  before_action :set_service, only: %i[edit update destroy]

  def index
    @services = Service.all.order(description: :asc)
  end

  def new
    @service = Service.new
  end

  def create
    @service = Service.new(service_params)
    if @service.save
      redirect_to services_path, notice: "Service created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to services_path, notice: "Service updated successfully."
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
    params.require(:service).permit(:description, :cost_price, :currency_cost_price, :sale_price, :currency_base_price, :value_units, :cost, :system_service_id)
  end
 
end
