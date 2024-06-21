class PeliculasController < ApplicationController
  before_action :set_pelicula, only: %i[ show edit update destroy ]

  # GET /peliculas or /peliculas.json
  def index
    @peliculas = Pelicula.all.with_attached_poster
  end

  # GET /peliculas/new
  def new
    @pelicula = Pelicula.new
  end

  # POST /peliculas or /peliculas.json
  def create
    @pelicula = Pelicula.new(pelicula_params)

    respond_to do |format|
      if @pelicula.save
        redirect_to products_path, notice: "La Pelicula se ha creado correctamente"
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

   # GET /peliculas/1 or /peliculas/1.json
   def show
   end
 

  # GET /peliculas/1/edit
  def edit
  end

  # PATCH/PUT /peliculas/1 or /peliculas/1.json
  def update
    respond_to do |format|
      if @pelicula.update(pelicula_params)
        format.html { redirect_to pelicula_url(@pelicula), notice: "La Pelicula se ha actualizado correctamente." }
        format.json { render :show, status: :ok, location: @pelicula }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @pelicula.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /peliculas/1 or /peliculas/1.json
  def destroy
    @pelicula.destroy!

    respond_to do |format|
      format.html { redirect_to peliculas_url, notice: "Pelicula was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_pelicula
      @pelicula = Pelicula.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def pelicula_params
      params.require(:pelicula).permit(:poster, :name, :others_titles, :year, :duration_hours, :duration_minutes, :director, :reparto, :sinopsis, :audio, :calidad, :formato_video, :codigo, :disponible, :link_trailer)
    end
end
