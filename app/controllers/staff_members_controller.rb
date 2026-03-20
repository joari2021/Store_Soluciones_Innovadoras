class StaffMembersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_business
  before_action :set_staff_member, only: %i[edit update destroy]

  def index
    @staff_members = User.includes(:business)
                         .order(admin: :desc, active: :desc)
                         .order(Arel.sql("LOWER(COALESCE(full_name, username)) ASC"))
  end

  def new
    @staff_member = @business.users.new(active: true, admin: false, personal: true)
  end

  def create
    @staff_member = @business.users.new(staff_member_params)
    apply_authorization_level(@staff_member)

    if @staff_member.save
      redirect_to business_staff_members_path(@business), notice: 'Usuario creado correctamente.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @staff_member.assign_attributes(staff_member_params)
    apply_authorization_level(@staff_member)

    if @staff_member.save
      redirect_to business_staff_members_path(@business), notice: 'Usuario actualizado correctamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @staff_member.id == Current.user&.id
      redirect_to business_staff_members_path(@business), alert: 'No puedes eliminar tu propio usuario activo.'
      return
    end

    if @staff_member.admin?
      admin_scope = User.where(admin: true)
      admin_scope = admin_scope.where(business_id: @staff_member.business_id) if @staff_member.business_id.present?

      if admin_scope.where.not(id: @staff_member.id).none?
        message = @staff_member.business_id.present? ? 'Debe existir al menos un administrador en el negocio.' : 'Debe existir al menos un administrador en el sistema.'
        redirect_to business_staff_members_path(@business), alert: message
        return
      end
    end

    @staff_member.destroy
    redirect_to business_staff_members_path(@business), notice: 'Usuario eliminado.'
  end

  private

  def set_business
    @business = Business.find(params[:business_id])
  end

  def set_staff_member
    @staff_member = User.find(params[:id])
  end

  def staff_member_params
    params.require(:user).permit(
      :full_name,
      :email,
      :username,
      :password,
      :password_confirmation,
      :active,
      :avatar
    )
  end

  def authorization_level_param
    raw_level = params.dig(:user, :authorization_level).to_s
    return raw_level if %w[administrator manager standard_staff].include?(raw_level)

    @staff_member&.role_key.presence || 'standard_staff'
  end

  def apply_authorization_level(user)
    case authorization_level_param
    when 'administrator'
      user.admin = true
      user.personal = false
      user.personal_saime = true if user.respond_to?(:personal_saime=)
      user.authorization_level = 'administrator' if user.respond_to?(:authorization_level=)
    when 'manager'
      user.admin = false
      user.personal = true
      user.personal_saime = false if user.respond_to?(:personal_saime=)
      user.authorization_level = 'manager' if user.respond_to?(:authorization_level=)
    else
      user.admin = false
      user.personal = true
      user.personal_saime = false if user.respond_to?(:personal_saime=)
      user.authorization_level = 'standard_staff' if user.respond_to?(:authorization_level=)
    end
  end
end
