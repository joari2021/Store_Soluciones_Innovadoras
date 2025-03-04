class SaimeUsersController < ApplicationController
  before_action :set_saime_user, only: [:show, :edit, :update, :destroy]

  def index
    @saime_users = SaimeUser.all
  end

  def show
  end

  def new
    @saime_user = SaimeUser.new
  end

  def create
    @saime_user = SaimeUser.new(saime_user_params)
    if @saime_user.save
      redirect_to @saime_user, notice: "SAIME User created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @saime_user.update(saime_user_params)
      redirect_to @saime_user, notice: "SAIME User updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @saime_user.destroy
    redirect_to saime_users_path, notice: "SAIME User deleted successfully."
  end

  private

  def set_saime_user
    @saime_user = SaimeUser.find(params[:id])
  end

  def saime_user_params
    params.require(:saime_user).permit(:identification, :entry, :temporary_status, :confirmed_status, :user_id)
  end
end
