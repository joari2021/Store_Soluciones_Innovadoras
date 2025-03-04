class AppointmentsController < ApplicationController
  before_action :set_appointment, only: [:show, :edit, :update, :destroy]
  before_action :set_saime_user, only: [:index, :new, :create]

  def index
    @appointments = @saime_user.appointments
  end

  def show
  end

  def new
    @appointment = @saime_user.appointments.build
  end

  def create
    @appointment = @saime_user.appointments.build(appointment_params)
    if @appointment.save
      redirect_to saime_user_appointments_path(@saime_user), notice: "Appointment created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @appointment.update(appointment_params)
      redirect_to @appointment, notice: "Appointment updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @appointment.destroy
    redirect_to appointments_path, notice: "Appointment deleted successfully."
  end

  private

  def set_appointment
    @appointment = Appointment.find(params[:id])
  end

  def set_saime_user
    @saime_user = SaimeUser.find(params[:saime_user_id])
  end

  def appointment_params
    params.require(:appointment).permit(:appointment_type, :appointment_date, :appointment_time, :status, :reschedulable)
  end
end
