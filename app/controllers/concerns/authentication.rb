module Authentication
  extend ActiveSupport::Concern

  INACTIVITY_TIMEOUT_SECONDS = 2.hours.to_i

  included do
    before_action :set_current_user
    before_action :protect_pages
    before_action :enforce_session_timeout

    private

    def set_current_user
      return unless session[:user_id]

      Current.user = User.find_by(id: session[:user_id], active: true)
      return if Current.user.present?

      session.delete(:user_id)
      session.delete(:business_id)
    end

    def enforce_session_timeout
      return unless request.format.html? || request.format.turbo_stream?
      return unless session[:user_id]

      last_seen_at = session[:last_seen_at].to_i
      now = Time.current.to_i

      if last_seen_at.positive? && (now - last_seen_at) > INACTIVITY_TIMEOUT_SECONDS
        reset_session
        redirect_to new_session_path, alert: "Tu sesion expiro por inactividad."
        return
      end

      session[:last_seen_at] = now if Current.user.present?
    end

    def protect_pages
      redirect_to new_session_path, alert: "Debes iniciar Sesion" unless Current.user
    end
  end
end
