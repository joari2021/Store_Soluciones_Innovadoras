class GlobalProfitMarginPresetsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_profit_margin_preset, only: %i[edit update destroy]

  def index
    @global_profit_margin_preset = GlobalProfitMarginPreset.new
    @global_profit_margin_presets = GlobalProfitMarginPreset.order(:percentage)
    @global_product_counts_by_percentage = global_product_counts_by_percentage
  end

  def create
    @global_profit_margin_preset = GlobalProfitMarginPreset.new(global_profit_margin_preset_params)

    if @global_profit_margin_preset.save
      redirect_to global_profit_margin_presets_path, notice: "Porcentaje fijo global creado exitosamente."
    else
      @global_profit_margin_presets = GlobalProfitMarginPreset.order(:percentage)
      @global_product_counts_by_percentage = global_product_counts_by_percentage
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    previous_percentage = @global_profit_margin_preset.percentage

    if @global_profit_margin_preset.update(global_profit_margin_preset_params)
      sync_global_products_fixed_margin(previous_percentage, @global_profit_margin_preset.percentage)
      redirect_to global_profit_margin_presets_path, notice: "Porcentaje fijo global actualizado exitosamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    clear_global_products_fixed_margin(@global_profit_margin_preset.percentage)

    if @global_profit_margin_preset.destroy
      redirect_to global_profit_margin_presets_path, notice: "Porcentaje fijo global eliminado exitosamente."
    else
      message = @global_profit_margin_preset.errors.full_messages.to_sentence.presence || "No se pudo eliminar el porcentaje fijo global."
      redirect_to global_profit_margin_presets_path, alert: message
    end
  end

  private

  def set_global_profit_margin_preset
    @global_profit_margin_preset = GlobalProfitMarginPreset.find(params[:id])
  end

  def global_profit_margin_preset_params
    params.require(:global_profit_margin_preset).permit(:percentage)
  end

  def global_product_counts_by_percentage
    GlobalProduct
      .all
      .map { |product| normalize_decimal(product.fixed_margin_percentage) }
      .compact
      .tally
  end

  def sync_global_products_fixed_margin(previous_percentage, new_percentage)
    old_value = normalize_decimal(previous_percentage)
    new_value = normalize_decimal(new_percentage)
    return if old_value.nil? || new_value.nil? || old_value == new_value

    GlobalProduct.find_each do |global_product|
      current_value = normalize_decimal(global_product.fixed_margin_percentage)
      next unless current_value == old_value

      global_product.assign_metadata_attributes!(fixed_margin_percentage: new_value.to_s("F"))
      global_product.save!(validate: false)
    end
  end

  def clear_global_products_fixed_margin(percentage)
    target_value = normalize_decimal(percentage)
    return if target_value.nil?

    GlobalProduct.find_each do |global_product|
      current_value = normalize_decimal(global_product.fixed_margin_percentage)
      next unless current_value == target_value

      global_product.assign_metadata_attributes!(fixed_margin_percentage: nil)
      global_product.save!(validate: false)
    end
  end

  def normalize_decimal(raw_value)
    return nil if raw_value.blank?
    return raw_value if raw_value.is_a?(BigDecimal)
    return BigDecimal(raw_value.to_s) if raw_value.is_a?(Numeric)

    compact = raw_value.to_s.strip.gsub(/\s+/, "").gsub(/[^\d,.-]/, "")
    return nil if compact.blank?

    normalized = if compact.include?(",")
        compact.delete(".").tr(",", ".")
      elsif compact.count(".") > 1 && compact.split(".").drop(1).all? { |group| group.length == 3 }
        compact.delete(".")
      else
        compact
      end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end
end
