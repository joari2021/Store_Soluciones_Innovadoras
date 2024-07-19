class ApplicationController < ActionController::Base
  before_action :set_current_user
  before_action :protect_pages

  def set_current_user
    Current.user = User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def protect_pages
    redirect_to new_session_path, alert: "debes iniciar sesion" unless Current.user
  end
end
