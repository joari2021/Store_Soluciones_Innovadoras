class DiscountSchedulesController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }
  before_action :set_discount_schedule, only: %i[edit update destroy]
  before_action :load_catalog_collections, only: %i[index create edit update]

  def index
    @discount_schedule = current_business.discount_schedules.new
    @discount_schedules = current_business.discount_schedules.order(active: :desc, updated_at: :desc, id: :desc)
  end

  def create
    @discount_schedule = current_business.discount_schedules.new(discount_schedule_params)
    @discount_schedules = current_business.discount_schedules.order(active: :desc, updated_at: :desc, id: :desc)

    if @discount_schedule.save
      redirect_to discount_schedules_path, notice: 'Descuento programado guardado correctamente.'
    else
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @discount_schedules = current_business.discount_schedules.where.not(id: @discount_schedule.id)
                                      .order(active: :desc, updated_at: :desc, id: :desc)
  end

  def update
    if @discount_schedule.update(discount_schedule_params)
      redirect_to discount_schedules_path, notice: 'Descuento programado actualizado correctamente.'
    else
      @discount_schedules = current_business.discount_schedules.where.not(id: @discount_schedule.id)
                                        .order(active: :desc, updated_at: :desc, id: :desc)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @discount_schedule.destroy
    redirect_to discount_schedules_path, notice: 'Descuento programado eliminado.'
  end

  private

  def set_discount_schedule
    @discount_schedule = current_business.discount_schedules.find(params[:id])
  end

  def discount_schedule_params
    permitted = params.require(:discount_schedule).permit(
      :name,
      :applies_to,
      :quantity_mode,
      :quantity_threshold,
      :discount_mode,
      :discount_value,
      :starts_on,
      :ends_on,
      :active,
      product_ids: [],
      service_ids: []
    )

    permitted[:starts_on] = parse_date_param(permitted[:starts_on])
    permitted[:ends_on] = parse_date_param(permitted[:ends_on])
    permitted[:discount_value] = parse_decimal_param(permitted[:discount_value])
    permitted
  end

  def load_catalog_collections
    @products = current_business.productos.order(:descripcion).select(:id, :descripcion, :presentation, :cant_presentation)
    @services = current_business.services.order(:description).select(:id, :description, :currency_base_price)
    @service_discount_symbols = build_service_discount_symbols(@services)
  end

  def parse_date_param(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    return Date.strptime(value.tr('/', '-'), '%d-%m-%Y') if value.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(value) if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(value)
  rescue ArgumentError
    nil
  end

  def parse_decimal_param(raw_value)
    compact = raw_value.to_s.strip.gsub(/\s+/, '').gsub(/[^\d.,-]/, '')
    return nil if compact.blank?

    normalized = if compact.include?(',')
        compact.gsub('.', '').tr(',', '.')
      elsif compact.match?(/^\d{1,3}(\.\d{3})+$/)
        compact.tr('.', '')
      else
        compact
      end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end

  def build_service_discount_symbols(services)
    Array(services).each_with_object({}) do |service, hash|
      reference = service.currency_base_price.to_s.strip
      if reference == Service::BOLIVAR_REFERENCE
        hash[service.id] = 'Bs'
      else
        symbol = TasaCambio.latest_symbol(reference).presence ||
                 TasaCambio::DEFAULT_SYMBOLS[reference] ||
                 '$'
        hash[service.id] = symbol
      end
    end
  end
end