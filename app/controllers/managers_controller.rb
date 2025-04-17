class ManagersController < ApplicationController
  before_action :set_manager, only: %i[edit update destroy]

  def index
    @managers = Manager.all.order(:name)
  end

  def new
    @manager = Manager.new
  end

  def create
    @manager = Manager.new(manager_params)
    if @manager.save
      redirect_to managers_path, notice: "Gestor creado exitosamente."
    else
      render :new
    end
  end

  def edit; end

  def update
    if @manager.update(manager_params)
      redirect_to managers_path, notice: "Gestor actualizado exitosamente."
    else
      render :edit
    end
  end

  def destroy
    @manager.destroy
    redirect_to managers_path, notice: "Gestor eliminado exitosamente."
  end

  private

  def set_manager
    @manager = Manager.find(params[:id])
  end

  def manager_params
    params.require(:manager).permit(:name, :cost)
  end
end