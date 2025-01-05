class TasaCambiosController < ApplicationController
  def edit
    @tasa_cambio = TasaCambio.last || TasaCambio.new
  end

  def update
    @tasa_cambio = TasaCambio.last || TasaCambio.new
    if @tasa_cambio.update(tasa_cambio_params)
      redirect_to productos_path, notice: "Tasa de cambio actualizada exitosamente."
    else
      render :edit
    end
  end

  private

  def tasa_cambio_params
    params.require(:tasa_cambio).permit(:valor)
  end
end
