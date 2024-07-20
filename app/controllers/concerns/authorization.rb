module Authorization
  extend ActiveSupport::Concern

  included do

    private

    def require_admin
      unless Current.user&.admin?
        flash[:alert] = "Acceso denegado."
        redirect_to peliculas_path
      end
    end
  end
end