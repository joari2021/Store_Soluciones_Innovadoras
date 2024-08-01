class PeliculasController < ApplicationController
  skip_before_action :protect_pages, only: [:index, :show]
  before_action :require_admin, except: [:index, :show]

  # GET /peliculas or /peliculas.json
  def index
    @generos = Genero.pluck(:name, :id)
    @peliculas = Pelicula.all.with_attached_poster
    @year_estreno = Pelicula.pluck(:date_estreno).map { |date| date.year }.uniq
    @clasifications_peliculas = Pelicula.distinct.pluck(:clasification)

    if params[:genero].present?
      @peliculas = Pelicula.joins(:generos).where(generos: { id: params[:genero] })
    end

    if params[:clasification].present?
      @peliculas = @peliculas.where(clasification: params[:clasification])
    end

    if params[:year_estreno].present?
      @peliculas = @peliculas.where("DATE_PART('year', date_estreno) = ?", params[:year_estreno].to_i)
    end

    if params[:query_text].present?
      @peliculas = @peliculas.whose_name_starts_with(params[:query_text])
    end

    order_by = Pelicula::ORDER_BY.fetch(params[:order_by]&.to_sym, Pelicula::ORDER_BY[:fecha_de_estreno_descendente])

    @peliculas = @peliculas.order(order_by)
  end

  # GET /peliculas/new
  def new
    @pelicula = Pelicula.new

    @editing = false
    @pelicula.rankings.build
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
    pelicula
  end

  # GET /peliculas/1/edit
  def edit
    pelicula
    @editing = true
  end

  # PATCH/PUT /peliculas/1 or /peliculas/1.json

  def update
    if pelicula.update(pelicula_params)
      redirect_to pelicula_url(pelicula), notice: "La Pelicula se ha actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /peliculas/1 or /peliculas/1.json
  def destroy
    pelicula.destroy!

    redirect_to peliculas_url, notice: "Pelicula was successfully destroyed."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def pelicula
    @pelicula ||= Pelicula.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def pelicula_params
    params.require(:pelicula).permit(:poster, :name, :others_titles, :date_estreno, :duration_hours, :duration_minutes, :director, :reparto, :sinopsis, :audio, :calidad, :formato_video, :codigo, :disponible, :link_trailer, :genero, :year_estreno, :clasification, rankings_attributes: [:id, :valor, :plataforma_pelicula_id, :_destroy], genero_ids: [])
  end
end
