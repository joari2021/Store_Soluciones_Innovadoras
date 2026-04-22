class GlobalCategoriesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_category, only: %i[edit update destroy]

  def index
    @global_category = GlobalCategory.new
    @global_categories = GlobalCategory.order(Arel.sql("LOWER(global_categories.name) ASC"))
    @global_product_counts_by_category_name = global_product_counts_by_category_name
  end

  def create
    @global_category = GlobalCategory.new(global_category_params)

    if @global_category.save
      redirect_to global_categories_path, notice: "Categoria global creada correctamente."
    else
      @global_categories = GlobalCategory.order(Arel.sql("LOWER(global_categories.name) ASC"))
      @global_product_counts_by_category_name = global_product_counts_by_category_name
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    previous_name = @global_category.name

    if @global_category.update(global_category_params)
      sync_global_products_category_name(previous_name, @global_category.name)
      redirect_to global_categories_path, notice: "Categoria global actualizada correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if global_products_for(@global_category.name).exists?
      redirect_to global_categories_path, alert: "No se puede eliminar esta categoria porque tiene productos globales asociados."
      return
    end

    if @global_category.destroy
      redirect_to global_categories_path, notice: "Categoria global eliminada correctamente."
    else
      message = @global_category.errors.full_messages.to_sentence.presence || "No se pudo eliminar la categoria global."
      redirect_to global_categories_path, alert: message
    end
  end

  private

  def set_global_category
    @global_category = GlobalCategory.find(params[:id])
  end

  def global_category_params
    params.require(:global_category).permit(:name)
  end

  def global_product_counts_by_category_name
    GlobalProduct
      .pluck(Arel.sql("COALESCE(NULLIF(TRIM(global_products.metadata->>'category_name'), ''), '')"))
      .map { |name| name.to_s.strip }
      .reject(&:blank?)
      .tally
  end

  def global_products_for(category_name)
    GlobalProduct.where("LOWER(TRIM(global_products.metadata->>'category_name')) = ?", category_name.to_s.strip.downcase)
  end

  def sync_global_products_category_name(previous_name, new_name)
    old_name = previous_name.to_s.strip
    updated_name = new_name.to_s.strip
    return if old_name.blank? || updated_name.blank?
    return if old_name.casecmp?(updated_name)

    GlobalProduct.find_each do |global_product|
      current_name = global_product.category_name.to_s.strip
      next unless current_name.casecmp?(old_name)

      global_product.assign_metadata_attributes!(category_name: updated_name)
      global_product.save!(validate: false)
    end
  end
end
