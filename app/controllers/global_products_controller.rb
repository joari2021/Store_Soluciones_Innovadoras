class GlobalProductsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_product, only: %i[edit update]

  def index
    @global_products = GlobalProduct
                       .includes(:source_business, :productos, :global_supplier_products)
                       .order(Arel.sql("LOWER(global_products.name) ASC"))
  end

  def new
    @global_product = GlobalProduct.new(presentation: :unidad, cant_presentation: 1)
  end

  def create
    @global_product = GlobalProduct.new(global_product_params)
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.save
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      redirect_to global_products_path, notice: "Producto global creado correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.update(global_product_params)
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      GlobalCatalog::SyncGlobalProductService.new(@global_product).call
      redirect_to global_products_path, notice: "Producto global actualizado y sincronizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_global_product
    @global_product = GlobalProduct.find(params[:id])
  end

  def global_product_params
    params.require(:global_product).permit(:name, :presentation, :cant_presentation, :exento, :active)
  end

  def global_product_metadata_params
    params.fetch(:global_product, {}).permit(
      :category_name,
      :fixed_margin_percentage,
      :real_margin_percentage,
      :sale_price_usd,
    )
  end
end
