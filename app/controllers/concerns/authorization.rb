module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_user_admin?, :current_user_standard_staff?, :current_user_manager?, :can_access_module?,
                  :can_manage_action?, :current_user_role_label, :current_user_customer_mode?,
                  :current_user_customer_vip_mode?

    private

    def require_admin
      return if Current.user&.admin?

      deny_access
    end

    def require_module_access!(module_key)
      return if can_access_module?(module_key)

      deny_access
    end

    def deny_access(message = "Acceso denegado.")
      respond_to do |format|
        format.html { redirect_to root_path, alert: message }
        format.json { render json: { error: message }, status: :forbidden }
      end
    end
  end

  def current_user_admin?
    user = Current.user
    return false unless user
    return true if user.admin?

    business = respond_to?(:current_business, true) ? send(:current_business) : Current.business
    user.role_key(business) == "administrator"
  end

  def current_user_standard_staff?
    Current.user&.standard_staff?
  end

  def current_user_manager?
    Current.user&.manager?
  end

  def can_access_module?(module_key)
    Current.user&.can_access_module?(module_key)
  end

  def can_manage_action?(action_key)
    Current.user&.can_manage_action?(action_key)
  end

  def current_user_role_label
    Current.user&.role_label.to_s
  end

  def current_user_customer_mode?
    business = respond_to?(:current_business, true) ? send(:current_business) : Current.business
    Current.user&.customer_mode?(business)
  end

  def current_user_customer_vip_mode?
    business = respond_to?(:current_business, true) ? send(:current_business) : Current.business
    Current.user&.customer_vip_mode?(business)
  end
end
