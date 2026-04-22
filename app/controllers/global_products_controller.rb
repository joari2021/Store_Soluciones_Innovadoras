class GlobalProductsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_product, only: %i[edit update]

  def index
    @global_products = GlobalProduct
                       .includes(:source_business, :productos, :global_supplier_products)
                       .order(Arel.sql("LOWER(global_products.name) ASC"))
  end

  def edit; end

  def update
    if @global_product.update(global_product_params)
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
end
