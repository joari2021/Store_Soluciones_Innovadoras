class VentaEliminadasController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :require_admin

  def index
    @venta_eliminadas = VentaEliminada.where(business_id: current_business.id).order(deleted_at: :desc).limit(200)
  end

  private

  def require_admin
    unless current_user_admin?
      return redirect_to historial_ventas_path, alert: 'Acceso denegado.'
    end
  end
end
