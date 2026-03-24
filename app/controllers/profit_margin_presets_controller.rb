class ProfitMarginPresetsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_profit_margin_preset, only: %i[edit update destroy]

  def index
    @profit_margin_preset = current_business.profit_margin_presets.new
    @profit_margin_presets = current_business.profit_margin_presets.order(percentage: :asc)
    @product_counts_by_preset_id = product_counts_by_preset
  end

  def create
    @profit_margin_preset = current_business.profit_margin_presets.new(profit_margin_preset_params)

    if @profit_margin_preset.save
      redirect_to profit_margin_presets_path, notice: 'Porcentaje fijo creado exitosamente.'
    else
      @profit_margin_presets = current_business.profit_margin_presets.order(percentage: :asc)
      @product_counts_by_preset_id = product_counts_by_preset
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @profit_margin_presets = current_business.profit_margin_presets.where.not(id: @profit_margin_preset.id).order(percentage: :asc)
    @product_counts_by_preset_id = product_counts_by_preset
  end

  def update
    if @profit_margin_preset.update(profit_margin_preset_params)
      redirect_to profit_margin_presets_path, notice: 'Porcentaje fijo actualizado exitosamente.'
    else
      @profit_margin_presets = current_business.profit_margin_presets.where.not(id: @profit_margin_preset.id).order(percentage: :asc)
      @product_counts_by_preset_id = product_counts_by_preset
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @profit_margin_preset.destroy
      redirect_to profit_margin_presets_path, notice: 'Porcentaje fijo eliminado exitosamente.'
    else
      message = @profit_margin_preset.errors.full_messages.to_sentence.presence || 'No se pudo eliminar el porcentaje fijo.'
      redirect_to profit_margin_presets_path, alert: message
    end
  end

  private

  def set_profit_margin_preset
    @profit_margin_preset = current_business.profit_margin_presets.find(params[:id])
  end

  def profit_margin_preset_params
    params.require(:profit_margin_preset).permit(:percentage)
  end

  def product_counts_by_preset
    return {} unless Producto.column_names.include?('profit_margin_preset_id')

    current_business.productos.group(:profit_margin_preset_id).count
  end
end
