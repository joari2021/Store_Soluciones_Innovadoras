class GenerosController < ApplicationController
  before_action :require_admin
  # GET /generos or /generos.json
  def index
    @generos = Genero.all.order(:name)
  end

  # GET /generos/new
  def new
    @genero = Genero.new
  end

  # GET /generos/1/edit
  def edit
    genero
  end

  # POST /generos or /generos.json
  def create
    @genero = Genero.new(genero_params)

    if @genero.save
      redirect_to generos_url, notice: "Genero was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /generos/1 or /generos/1.json
  def update
    if genero.update(genero_params)
      redirect_to generos_url, notice: "Genero was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /generos/1 or /generos/1.json
  def destroy
    genero.destroy!

    redirect_to generos_url, notice: "Genero was successfully destroyed."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def genero
    @genero = Genero.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def genero_params
    params.require(:genero).permit(:name)
  end
end
