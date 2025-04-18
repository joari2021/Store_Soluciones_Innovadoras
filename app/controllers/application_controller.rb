class ApplicationController < ActionController::Base
  before_action :set_tasas

  include Authentication
  include Authorization
  include Pagy::Backend

  private

  def set_tasas
    @tasa_dolar_bcv = TasaCambio.find_by(description: "Dolar BCV")&.valor || "No disponible"
    @tasa_dolar_paralelo = TasaCambio.find_by(description: "Dolar Paralelo")&.valor || "No disponible"
    @tasa_dolar_promedio = TasaCambio.find_by(description: "Dolar Promedio")&.valor || "No disponible"
    @unidad_VI = TasaCambio.find_by(description: "Unidad VI")&.valor || "No disponible"
    @tasas = TasaCambio.all.each_with_object({}) { |tasa, hash| hash[tasa.description] = tasa.valor }
  end
end



  