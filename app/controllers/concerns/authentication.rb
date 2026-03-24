module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    before_action :protect_pages

    private

    def set_current_user
      return unless session[:user_id]

      Current.user = User.find_by(id: session[:user_id], active: true)
      return if Current.user.present?

      session.delete(:user_id)
      session.delete(:business_id)
    end

    def protect_pages
      redirect_to new_session_path, alert: 'Debes iniciar Sesion' unless Current.user
    end
  end
end
