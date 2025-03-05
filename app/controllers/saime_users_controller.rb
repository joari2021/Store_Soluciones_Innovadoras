class SaimeUsersController < ApplicationController
  before_action :set_saime_user, only: %i[show edit update destroy]

  def new
    @saime_user = SaimeUser.new
    @saime_user.appointments.build(appointment_type: next_appointment_type(@saime_user))
  end

  def create
    @saime_user = SaimeUser.new(saime_user_params)

    if @saime_user.save
      redirect_to saime_users_path, notice: "Saime User and Appointments created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_saime_user
    @saime_user = SaimeUser.find(params[:id])
  end

  def saime_user_params
    params.require(:saime_user).permit(:identification, :entry, 
      appointments_attributes: [:id, :appointment_date, :appointment_type, :_destroy])
  end

  def next_appointment_type(saime_user)
    case saime_user.appointments.count
    when 0 then "cedula"
    when 1 then "civil"
    else "niño"
    end
  end
end
