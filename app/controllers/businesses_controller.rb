class BusinessesController < ApplicationController
  before_action :require_admin, except: %i[select]
  before_action :set_business, only: %i[edit update destroy select]
  before_action :ensure_can_select_business!, only: %i[select]

  def index
    @businesses = Business.order(:name)
  end

  def new
    @business = Business.new
  end

  def create
    @business = Business.new(business_params)
    if @business.save
      session[:business_id] = @business.id
      Current.business = @business if Current.is_a?(Class) && Current.respond_to?(:business=)
      redirect_to businesses_path, notice: 'Negocio creado correctamente.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @business.update(business_params)
      redirect_to businesses_path, notice: 'Negocio actualizado correctamente.'
    else
      render :edit
    end
  end

  def destroy
    was_current = session[:business_id].to_i == @business.id
    @business.destroy

    if was_current
      session[:business_id] = Business.order(:name).first&.id
      if Current.is_a?(Class) && Current.respond_to?(:business=)
        Current.business = Business.find_by(id: session[:business_id])
      end
    end

    redirect_to businesses_path, notice: 'Negocio eliminado correctamente.'
  end

  def select
    session[:business_id] = @business.id
    Current.business = @business if Current.is_a?(Class) && Current.respond_to?(:business=)
    redirect_to ventas_path, notice: "Negocio seleccionado: #{@business.name}."
  end

  private

  def set_business
    @business = Business.find(params[:id])
  end

  def business_params
    params.require(:business).permit(
      :name,
      :theme_profile,
      :phone,
      :city,
      :state,
      :address,
      :rif,
      :logo,
      :banner,
      :hide_initial_inventory_button
    )
  end

  def ensure_can_select_business!
    return if current_user_admin?
    return if Current.user&.assigned_to_business?(@business)

    deny_access('No tienes acceso al negocio seleccionado.')
  end
end
