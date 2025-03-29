class SaimeUsersController < ApplicationController
  before_action :set_saime_user, only: %i[show edit update destroy]
  def index
    @saime_users = SaimeUser
      .left_joins(:appointments)
      .select("saime_users.*, MIN(CASE WHEN appointments.status = 'activa' THEN appointments.appointment_date ELSE NULL END) as nearest_active_date")
      .group("saime_users.id")
      .order("nearest_active_date ASC NULLS LAST")
  end
  def new
    @saime_user = SaimeUser.new
    @saime_user.appointments.build(appointment_type: next_appointment_type(@saime_user))
  end

  def create
    @saime_user = SaimeUser.new(saime_user_params)

    if @saime_user.save
      flash[:notice] = "Registro Completado Exitosamente"
      redirect_to saime_users_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # @saime_user ya se carga en el before_action
  end

  # PATCH/PUT /saime_users/:id
  def update
    if @saime_user.update(saime_user_params)
      redirect_to saime_users_path, notice: 'El usuario se actualizó correctamente.'
    else
      render :edit
    end
  end

  def destroy
  end


  private

  def set_saime_user
    @saime_user = SaimeUser.find(params[:id])
  end

  def saime_user_params
    params.require(:saime_user).permit(
      :identification, :entry, :temporary_status, :confirmed_status,
      appointments_attributes: [:id, :appointment_date, :appointment_type, :reschedulable, :_destroy]
    )
  end
  

  def next_appointment_type(saime_user)
    case saime_user.appointments.count
    when 0 then "cedula"
    when 1 then "civil"
    else "niño"
    end
  end
end
