class GlobalSupplierProductsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_supplier_product

  def edit; end

  def update
    if @global_supplier_product.update(global_supplier_product_params)
      redirect_to edit_global_supplier_path(@global_supplier_product.global_supplier_id),
                  notice: "Costo global actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_global_supplier_product
    @global_supplier_product = GlobalSupplierProduct
                               .includes(:global_supplier, :global_product)
                               .find(params[:id])
  end

  def global_supplier_product_params
    params.require(:global_supplier_product).permit(:costo_mayor, :cantidad, :costo_menor, :active)
  end
end
