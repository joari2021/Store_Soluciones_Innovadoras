class ApplicationController < ActionController::Base
  before_action :set_tasas

  include Authentication
  include Authorization
  include Pagy::Backend

  private

  def set_tasas
    @tasa_dolar_bcv = TasaCambio.find_by(description: "Dolar BCV")&.valor || "No disponible"
    @tasa_dolar_paralelo = TasaCambio.find_by(description: "Dolar Paralelo")&.valor || "No disponible"
    @unidad_VI = TasaCambio.find_by(description: "Unidad VI")&.valor || "No disponible"
  end
end



  