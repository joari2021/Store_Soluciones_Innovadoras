class PeliculasController < ApplicationController
  before_action :set_pelicula, only: %i[ show edit update destroy ]

  # GET /peliculas or /peliculas.json
  def index
    @generos = Genero.order(name: :asc).load_async
    @peliculas = Pelicula.all.with_attached_poster

    if params[:genero_id]
      @peliculas = Pelicula.joins(:generos).where(generos: { id: params[:genero_id] })
    end
  end

  # GET /peliculas/new
  def new
    @pelicula = Pelicula.new
  end

  # POST /peliculas or /peliculas.json
  def create
    @pelicula = Pelicula.new(pelicula_params)

    if @pelicula.save
      redirect_to peliculas_path, notice: "La Pelicula se ha creado correctamente"
    else
      render :new, status: :unprocessable_entity
    end
  end

   # GET /peliculas/1 or /peliculas/1.json
   def show
    set_pelicula
   end
 

  # GET /peliculas/1/edit
  def edit
  end

  # PATCH/PUT /peliculas/1 or /peliculas/1.json
  def update
    if @pelicula.update(pelicula_params)
      redirect_to pelicula_url(@pelicula), notice: "La Pelicula se ha actualizado correctamente." 
    else
      render :edit, status: :unprocessable_entity 
    end
  end

  # DELETE /peliculas/1 or /peliculas/1.json
  def destroy
    @pelicula.destroy!

    redirect_to peliculas_url, notice: "Pelicula was successfully destroyed."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_pelicula
      @pelicula ||= Pelicula.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def pelicula_params
      params.require(:pelicula).permit(:poster, :name, :others_titles, :year, :duration_hours, :duration_minutes, :director, :reparto, :sinopsis, :audio, :calidad, :formato_video, :codigo, :disponible, :link_trailer, genero_ids: [])
    end
end
