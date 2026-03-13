class TasaCambiosController < ApplicationController
  before_action :set_tasa_cambio, only: %i[show edit update destroy]

  def bcv_por_fecha
    fecha = parse_fecha(params[:fecha])
    return render json: { error: 'Fecha inválida' }, status: :unprocessable_entity if fecha.blank?

    tasa = TasaCambio.find_by(description: 'Dolar BCV', fecha_referencia: fecha)
    if tasa.present?
      render json: {
        valor: tasa.valor,
        symbol: tasa.symbol,
        fecha_referencia: tasa.fecha_referencia
      }
    else
      render json: { error: 'No hay tasa Dolar BCV registrada para esta fecha de referencia' }, status: :not_found
    end
  end

  def index
    @bcv_ssl_status = (ScraperStatus.bcv_ssl if ActiveRecord::Base.connection.data_source_exists?('scraper_statuses'))

    @tasa_cambios = TasaCambio
                    .select('DISTINCT ON (description) tasa_cambios.*')
                    .order('description ASC, fecha_referencia DESC, created_at DESC')
  end

  def scrape_bcv
    result = BcvScraperService.call
    if result.blank?
      redirect_to tasa_cambios_path, alert: 'No se pudo actualizar la tasa BCV.'
    elsif result[:status] == :up_to_date
      redirect_to tasa_cambios_path, flash: { warning: 'Las tasas BCV ya estan actualizadas.' }
    else
      redirect_to tasa_cambios_path, notice: 'Scraper BCV ejecutado correctamente.'
    end
  end

  def scrape_usdt
    result = BybitUsdtScraperService.call
    if result.present?
      redirect_to tasa_cambios_path, notice: 'Scraper USDT ejecutado correctamente.'
    else
      redirect_to tasa_cambios_path, alert: 'No se pudo actualizar la tasa USDT.'
    end
  end

  def new
    description = params[:description]
    @tasa_cambio = TasaCambio.new(
      description: description,
      symbol: TasaCambio.latest_symbol(description) || TasaCambio::DEFAULT_SYMBOLS[description]
    )
  end

  def show
    @fecha_filtro = params[:fecha]
    @fecha_filtro_display = begin
      parsed = parse_fecha(@fecha_filtro)
      parsed ? parsed.strftime('%d-%m-%Y') : @fecha_filtro
    rescue ArgumentError
      @fecha_filtro
    end
    @historial_tasas = TasaCambio.where(description: @tasa_cambio.description)

    if @fecha_filtro.present?
      fecha = parse_fecha(@fecha_filtro)
      @historial_tasas = @historial_tasas.where(fecha_referencia: fecha) if fecha.present?
    end

    @historial_tasas = @historial_tasas.order(fecha_referencia: :desc, created_at: :desc)
    @show_percentage_change = ['Dolar BCV', 'Euro BCV'].include?(@tasa_cambio.description)

    if @show_percentage_change
      @historial_tasas = @historial_tasas.select(<<~SQL.squish)
        tasa_cambios.*,
        LEAD(tasa_cambios.valor) OVER (
          ORDER BY tasa_cambios.fecha_referencia DESC, tasa_cambios.created_at DESC
        ) AS previous_valor
      SQL
    end

    @pagy, @historial_tasas = pagy(@historial_tasas, items: 20)
  end

  def create
    @tasa_cambio = TasaCambio.new(tasa_cambio_params)
    if @tasa_cambio.save
      redirect_to tasa_cambios_path, notice: 'Tasa de cambio creada exitosamente.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @tasa_cambio.update(tasa_cambio_params)
      redirect_to tasa_cambios_path, notice: 'Tasa de cambio actualizada exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tasa_cambio.destroy
    redirect_to tasa_cambios_path, notice: 'Tasa de cambio eliminada exitosamente.'
  end

  private

  def set_tasa_cambio
    @tasa_cambio = TasaCambio.find(params[:id])
  end

  def tasa_cambio_params
    params.require(:tasa_cambio).permit(:valor, :description, :fecha_referencia, :symbol)
  end

  def parse_fecha(raw_fecha)
    return if raw_fecha.blank?

    Date.parse(raw_fecha)
  rescue ArgumentError
    nil
  end
end
