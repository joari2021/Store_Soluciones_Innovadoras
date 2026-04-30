class StaffMembersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_business
  before_action :set_staff_member, only: %i[edit update destroy]

  def index
    @staff_members = User.includes(:business, :business_user_assignments, :assigned_businesses)
                         .order(admin: :desc, active: :desc)
                         .order(Arel.sql("LOWER(COALESCE(full_name, username)) ASC"))
  end

  def new
    @staff_member = User.new(active: true, admin: false, personal: true, business: @business)
  end

  def create
    @staff_member = User.new(staff_member_params)

    User.transaction do
      @staff_member.save!
      sync_business_assignments!(@staff_member)
    end

    redirect_to business_staff_members_path(@business), notice: "Usuario creado correctamente."
  rescue ActiveRecord::RecordInvalid
    if @staff_member.business_user_assignments.empty?
      @staff_member.errors.add(:base, "Debes asignar al menos un negocio al usuario.")
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    @staff_member.assign_attributes(staff_member_params)

    User.transaction do
      @staff_member.save!
      sync_business_assignments!(@staff_member)
    end

    redirect_to business_staff_members_path(@business), notice: "Usuario actualizado correctamente."
  rescue ActiveRecord::RecordInvalid
    if @staff_member.business_user_assignments.empty?
      @staff_member.errors.add(:base, "Debes asignar al menos un negocio al usuario.")
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @staff_member.id == Current.user&.id
      redirect_to business_staff_members_path(@business), alert: "No puedes eliminar tu propio usuario activo."
      return
    end

    if @staff_member.admin?
      if User.where(admin: true).where.not(id: @staff_member.id).none?
        redirect_to business_staff_members_path(@business), alert: "Debe existir al menos un administrador en el sistema."
        return
      end
    end

    @staff_member.destroy
    redirect_to business_staff_members_path(@business), notice: "Usuario eliminado."
  end

  private

  def set_business
    @business = Business.find(params[:business_id])
  end

  def set_staff_member
    @staff_member = User.find(params[:id])

    return if @staff_member.admin?
    return if @staff_member.assigned_to_business?(@business)

    redirect_to business_staff_members_path(@business), alert: "Este usuario no esta asignado al negocio seleccionado."
  end

  def staff_member_params
    params.require(:user).permit(
      :full_name,
      :email,
      :username,
      :sex,
      :password,
      :password_confirmation,
      :active,
      :avatar
    )
  end


  def selected_assignment_business_ids
    raw_ids = Array(params.dig(:user, :assignment_business_ids)).map(&:to_s).map(&:strip)
    ids = raw_ids.reject(&:blank?).map(&:to_i).select(&:positive?).uniq
    ids = [@business.id] if ids.empty?
    ids
  end

  def assignment_role_for(business_id)
    role_map = params.dig(:user, :business_roles)
    role = role_map.is_a?(ActionController::Parameters) || role_map.is_a?(Hash) ? role_map[business_id.to_s] : nil
    role = role.to_s

    return 'none' if role == 'catalog_viewer'

    return 'manager' if role == 'administrator'
    return role if %w[none manager standard_staff].include?(role)

    existing = @staff_member.business_user_assignments.find { |assignment| assignment.business_id == business_id }
    legacy_level = existing&.authorization_level.to_s
    return 'manager' if legacy_level == 'administrator'

    legacy_level.presence || "none"
  end

  def assignment_customer_access_for(business_id)
    role_map = params.dig(:user, :business_roles)
    role = role_map.is_a?(ActionController::Parameters) || role_map.is_a?(Hash) ? role_map[business_id.to_s] : nil
    return 'catalog_viewer' if role.to_s == 'catalog_viewer'

    access_map = params.dig(:user, :business_customer_access)
    level = access_map.is_a?(ActionController::Parameters) || access_map.is_a?(Hash) ? access_map[business_id.to_s] : nil
    level = level.to_s

    return level if BusinessUserAssignment::CUSTOMER_ACCESS_LEVELS.include?(level)

    existing = @staff_member.business_user_assignments.find { |assignment| assignment.business_id == business_id }
    existing&.customer_access_level.presence || "none"
  end

  def sync_business_assignments!(user)
    if user.admin?
      user.business_user_assignments.destroy_all
      sync_legacy_business_id!(user, preferred_business_id: @business.id)
      return
    end

    ids = selected_assignment_business_ids

    user.business_user_assignments.where.not(business_id: ids).destroy_all

    ids.each do |business_id|
      assignment = user.business_user_assignments.find_or_initialize_by(business_id: business_id)
      assignment.authorization_level = assignment_role_for(business_id)
      assignment.customer_access_level = assignment_customer_access_for(business_id)
      assignment.active = user.active?
      assignment.save!
    end

    sync_legacy_business_id!(user, preferred_business_id: ids.first)
  end

  def sync_legacy_business_id!(user, preferred_business_id: nil)
    fallback_business_id = preferred_business_id || user.business_user_assignments.order(:created_at).limit(1).pick(:business_id)
    return if user.business_id == fallback_business_id

    user.update_column(:business_id, fallback_business_id)
  end
end
