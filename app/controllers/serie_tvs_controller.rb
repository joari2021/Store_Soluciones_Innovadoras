class SerieTvsController < ApplicationController
  before_action :set_serie_tv, only: %i[ show edit update destroy ]

  # GET /serie_tvs or /serie_tvs.json
  def index
    @serie_tvs = SerieTv.all
  end

  # GET /serie_tvs/1 or /serie_tvs/1.json
  def show
  end

  # GET /serie_tvs/new
  def new
    @serie_tv = SerieTv.new
  end

  # GET /serie_tvs/1/edit
  def edit
  end

  # POST /serie_tvs or /serie_tvs.json
  def create
    @serie_tv = SerieTv.new(serie_tv_params)

    respond_to do |format|
      if @serie_tv.save
        format.html { redirect_to serie_tv_url(@serie_tv), notice: "Serie tv was successfully created." }
        format.json { render :show, status: :created, location: @serie_tv }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @serie_tv.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /serie_tvs/1 or /serie_tvs/1.json
  def update
    respond_to do |format|
      if @serie_tv.update(serie_tv_params)
        format.html { redirect_to serie_tv_url(@serie_tv), notice: "Serie tv was successfully updated." }
        format.json { render :show, status: :ok, location: @serie_tv }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @serie_tv.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /serie_tvs/1 or /serie_tvs/1.json
  def destroy
    @serie_tv.destroy!

    respond_to do |format|
      format.html { redirect_to serie_tvs_url, notice: "Serie tv was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_serie_tv
      @serie_tv = SerieTv.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def serie_tv_params
      params.require(:serie_tv).permit(:poster, :name, :others_title, :year, :temporadas, :capitulos, :director, :reparto, :sinopsis, :audio, :calidad, :status, :formato_video, :codigo, :disponible, :link_trailer)
    end
end
