class Authentication::UsersController < ApplicationController
  skip_before_action :protect_pages
  skip_before_action :set_tasas
  skip_before_action :set_business_context

  layout 'authentication'

  before_action :redirect_if_registration_closed

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.admin = true
    @user.personal = false
    @user.personal_saime = true if @user.respond_to?(:personal_saime=)
    @user.active = true if @user.respond_to?(:active=)

    if @user.save
      session[:user_id] = @user.id
      redirect_to root_path, notice: 'Te has registrado con exito'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_registration_closed
    return if !User.exists? || Current.user&.admin?

    redirect_to new_session_path, alert: 'El registro publico esta deshabilitado. Solicita acceso al administrador.'
  end

  def user_params
    params.require(:user).permit(:full_name, :email, :username, :password, :password_confirmation)
  end
end
