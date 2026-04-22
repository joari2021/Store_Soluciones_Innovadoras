class GlobalSuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_supplier, only: %i[edit update]

  def index
    @global_suppliers = GlobalSupplier
                        .includes(:source_business, :suppliers, :global_supplier_products)
                        .order(Arel.sql("LOWER(global_suppliers.name) ASC"))
  end

  def edit
    @global_supplier_products = @global_supplier.global_supplier_products
                                               .includes(:global_product)
                                               .order(Arel.sql("LOWER(global_products.name) ASC"))
  end

  def update
    if @global_supplier.update(global_supplier_params)
      GlobalCatalog::SyncGlobalSupplierService.new(@global_supplier).call
      redirect_to global_suppliers_path, notice: "Proveedor global actualizado y sincronizado."
    else
      @global_supplier_products = @global_supplier.global_supplier_products.includes(:global_product)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_global_supplier
    @global_supplier = GlobalSupplier.find(params[:id])
  end

  def global_supplier_params
    params.require(:global_supplier).permit(
      :name,
      :rif,
      :phone,
      :mobile_payment_phone,
      :email,
      :address,
      :bank_account_number,
      :pricing_currency_priority,
      :default_exento,
      :active,
    )
  end
end
