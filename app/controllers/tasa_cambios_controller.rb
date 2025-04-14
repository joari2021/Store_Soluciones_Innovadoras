class TasaCambiosController < ApplicationController
  before_action :set_tasa_cambio, only: %i[edit update destroy]

  def index
    @tasa_cambios = TasaCambio.all.order(description: :asc)
  end

  def new
    @tasa_cambio = TasaCambio.new
  end

  def create
    @tasa_cambio = TasaCambio.new(tasa_cambio_params)
    if @tasa_cambio.save
      redirect_to tasa_cambios_path, notice: "Tasa de cambio creada exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @tasa_cambio.update(tasa_cambio_params)
      redirect_to tasa_cambios_path, notice: "Tasa de cambio actualizada exitosamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tasa_cambio.destroy
    redirect_to tasa_cambios_path, notice: "Tasa de cambio eliminada exitosamente."
  end

  private

  def set_tasa_cambio
    @tasa_cambio = TasaCambio.find(params[:id])
  end

  def tasa_cambio_params
    params.require(:tasa_cambio).permit(:valor, :description)
  end
end