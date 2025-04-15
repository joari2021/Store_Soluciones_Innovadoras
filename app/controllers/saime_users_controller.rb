class SaimeUsersController < ApplicationController
  before_action :set_saime_user, only: %i[show edit update destroy]

  # Primero, se verifica que el usuario tenga al menos alguno de los permisos
  before_action :require_permission
  # Para las acciones distintas de index y destroy, se requiere permiso SAIME
  before_action :require_personal_saime, except: [:index, :destroy]
  # Bloquear el acceso al método destroy para todos (incluso para personal_saime true)
  before_action :require_admin, only: [:destroy]

  def index
    # Primero, aseguramos que exista un usuario actual
    unless Current.user
      flash[:alert] = "Debes iniciar sesión."
      redirect_to login_path and return
    end

    # Asumimos que Current.user.personal y Current.user.personal_saime son booleanos.
    # Si el usuario tiene personal_saime = true, puede usar cualquier filtro.
    # Si tiene personal = true y personal_saime = false, forzamos el filtro a "disponible".
    if Current.user.personal_saime?
      filter = params[:filter] || "disponible"
    elsif Current.user.personal?
      filter = "disponible"
    else
      flash[:alert] = "No tienes permiso para acceder a esta sección."
      redirect_to root_path and return
    end
    
    @saime_users = case filter
    when "inprogramable"
      SaimeUser.with_non_schedulable_appointments
    when "apartadas"
      SaimeUser.with_reserved_appointments
    when "temporarily_blocked"
      SaimeUser.temporarily_blocked
    when "blocked"
      SaimeUser.blocked
    when "registros_disponibles"
      SaimeUser.without_appointments
    when "por_agendar"
      Current.user ? SaimeUser.where(user_id: Current.user.id, appointment_registration: false) : SaimeUser.none
    else #CITAS DISPONIBLES
      users = SaimeUser.with_available_appointments

      # Filtrar por rango de fechas si los parámetros están presentes
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date]) rescue nil
        end_date = Date.parse(params[:end_date]) rescue nil

        if start_date && end_date
          users = users.joins(:appointments)
                      .where(appointments: { appointment_date: start_date..end_date })
        end
      end
      users
    end
    @pagy, @saime_users = pagy_countless(@saime_users, items: 24) 
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
      redirect_to saime_users_path(filter: params[:filter]), notice: 'El usuario se actualizó correctamente.'
    else
      render :edit
    end
  end

  def destroy
  end

  def assign
    if request.get?
      return # Evita ejecutar este método si es una solicitud GET (como la búsqueda)
    end

    selected_ids = params[:selected_saime_users] || []
    if selected_ids.any?
      SaimeUser.where(id: selected_ids).update_all(user_id: Current.user.id, appointment_registration: false)
      flash[:notice] = "Usuarios asignados correctamente."
      redirect_to saime_users_path(filter: "por_agendar")
    else
      flash[:alert] = "No se seleccionó ningún usuario."
      redirect_to saime_users_path(filter: "registros_disponibles")
    end
  end

  private

  def set_saime_user
    @saime_user = SaimeUser.find(params[:id])
  end

  def saime_user_params
    params.require(:saime_user).permit(
      :identification, :entry, :temporary_status, :confirmed_status, :appointment_registration,
      appointments_attributes: [:id, :appointment_date, :appointment_type, :status, :client, :_destroy]
    )
  end
  

  def next_appointment_type(saime_user)
    case saime_user.appointments.count
    when 0 then "cedula"
    when 1 then "civil"
    else "niño"
    end
  end

  # Requiere que Current.user.personal o Current.user.personal_saime sea true
  def require_permission
    unless Current.user&.personal || Current.user&.personal_saime
      flash[:alert] = "Acceso denegado: No tienes permisos para acceder a esta sección."
      redirect_to root_path
    end
  end

  # Para acciones (distintas de index y destroy), se requiere que Current.user.personal_saime sea true
  def require_personal_saime
    unless Current.user&.personal_saime
      flash[:alert] = "Acceso denegado: Solo usuarios con permiso pueden acceder a esta sección."
      redirect_to root_path
    end
  end

  # Bloquea el método destroy para todos
  def require_admin
    unless Current.user&.admin
      flash[:alert] = "No tienes permiso para eliminar registros."
      redirect_to root_path
    end
  end
end
