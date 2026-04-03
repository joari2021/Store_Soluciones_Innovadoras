class Authentication::SessionsController < ApplicationController
  skip_before_action :protect_pages
  skip_before_action :set_tasas
  skip_before_action :set_business_context

  layout "authentication"

  def new
  end

  def create
    @user = User.find_by("email = :login OR username = :login", { login: params[:login] })

    if @user&.active? && @user.authenticate(params[:password])
      session[:user_id] = @user.id
      session[:business_id] = @user.business_id if @user.business_id.present?
      session[:last_seen_at] = Time.current.to_i
      redirect_to ventas_path, notice: "Haz iniciado sesion correctamente"
    elsif @user.present? && !@user.active?
      redirect_to new_session_path, alert: "Tu usuario esta inactivo. Contacta al administrador del negocio."
    else
      redirect_to new_session_path, alert: "Usuario o contrasena invalida"
    end
  end

  def destroy
    reset_session

    redirect_to new_session_path, notice: "Sesion finalizada"
  end
end
