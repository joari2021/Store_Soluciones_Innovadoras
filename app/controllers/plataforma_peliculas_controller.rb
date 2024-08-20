class PlataformaPeliculasController < ApplicationController
  before_action :set_plataforma_pelicula, only: %i[ edit update destroy ]

  # GET /plataforma_peliculas or /plataforma_peliculas.json
  def index
    @plataforma_peliculas = PlataformaPelicula.all.order_by("name ASC")
  end

  # GET /plataforma_peliculas/new
  def new
    @plataforma_pelicula = PlataformaPelicula.new
  end

  # GET /plataforma_peliculas/1/edit
  def edit
  end

  # POST /plataforma_peliculas or /plataforma_peliculas.json
  def create
    @plataforma_pelicula = PlataformaPelicula.new(plataforma_pelicula_params)

    respond_to do |format|
      if @plataforma_pelicula.save
        format.html { redirect_to plataforma_peliculas_path, notice: "Plataforma pelicula was successfully created." }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @plataforma_pelicula.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /plataforma_peliculas/1 or /plataforma_peliculas/1.json
  def update
    respond_to do |format|
      if @plataforma_pelicula.update(plataforma_pelicula_params)
        format.html { redirect_to plataforma_peliculas_path, notice: "Plataforma pelicula was successfully updated." }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @plataforma_pelicula.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /plataforma_peliculas/1 or /plataforma_peliculas/1.json
  def destroy
    @plataforma_pelicula.destroy!

    respond_to do |format|
      format.html { redirect_to plataforma_peliculas_path, notice: "Plataforma pelicula was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_plataforma_pelicula
    @plataforma_pelicula = PlataformaPelicula.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def plataforma_pelicula_params
    params.require(:plataforma_pelicula).permit(:name, :escala)
  end
end
