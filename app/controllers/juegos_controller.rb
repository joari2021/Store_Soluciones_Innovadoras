class JuegosController < ApplicationController
  before_action :set_juego, only: %i[ show edit update destroy ]

  # GET /juegos or /juegos.json
  def index
    @juegos = Juego.all
  end

  # GET /juegos/1 or /juegos/1.json
  def show
  end

  # GET /juegos/new
  def new
    @juego = Juego.new
  end

  # GET /juegos/1/edit
  def edit
  end

  # POST /juegos or /juegos.json
  def create
    @juego = Juego.new(juego_params)

    respond_to do |format|
      if @juego.save
        format.html { redirect_to juego_url(@juego), notice: "Juego was successfully created." }
        format.json { render :show, status: :created, location: @juego }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @juego.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /juegos/1 or /juegos/1.json
  def update
    respond_to do |format|
      if @juego.update(juego_params)
        format.html { redirect_to juego_url(@juego), notice: "Juego was successfully updated." }
        format.json { render :show, status: :ok, location: @juego }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @juego.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /juegos/1 or /juegos/1.json
  def destroy
    @juego.destroy!

    respond_to do |format|
      format.html { redirect_to juegos_url, notice: "Juego was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_juego
      @juego = Juego.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def juego_params
      params.require(:juego).permit(:poster, :name, :year, :desarrollador, :plataforma, :sinopsis, :audio, :calidad, :formato_video, :codigo, :disponible, :link_trailer)
    end
end
