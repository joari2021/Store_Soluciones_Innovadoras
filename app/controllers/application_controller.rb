class ApplicationController < ActionController::Base
  before_action :set_tasas
  before_action :set_business_context

  include Authentication
  include Authorization
  include Pagy::Backend

  private

  def set_tasas
    @tasa_dolar_bcv = TasaCambio.latest_value('Dolar BCV') || 'No disponible'
    @tasa_euro_bcv = TasaCambio.latest_value('Euro BCV') || 'No disponible'
    @unidad_VI = TasaCambio.latest_value('Unidad VI') || 'No disponible'
    @tasa_dolar_bcv_symbol = TasaCambio.latest_symbol('Dolar BCV') || '$'
    @tasa_euro_bcv_symbol = TasaCambio.latest_symbol('Euro BCV') || '€'
    @unidad_VI_symbol = TasaCambio.latest_symbol('Unidad VI') || 'Bs'
    @tasas = TasaCambio.latest_values_by_description
    @latest_tasas = TasaCambio
                    .select('DISTINCT ON (description) tasa_cambios.*')
                    .order('description ASC, fecha_referencia DESC, created_at DESC')
  end

  def set_business_context
    return unless ActiveRecord::Base.connection.data_source_exists?('businesses')

    @businesses = Business.order(:name)
    @current_business = if session[:business_id].present?
                          @businesses.find { |business| business.id == session[:business_id].to_i }
                        end
    @current_business ||= @businesses.first

    session[:business_id] = @current_business&.id
    return unless Current.is_a?(Class) && Current.respond_to?(:business=)

    Current.business = @current_business
  end

  attr_reader :current_business

  def require_business
    return if current_business.present?

    redirect_to new_business_path, alert: 'Crea un negocio para continuar.'
  end
  helper_method :current_business
end
