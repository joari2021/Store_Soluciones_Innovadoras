class GlobalSuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_supplier, only: %i[show edit update]
  before_action :set_tasa_dolar_bcv, only: %i[show]

  def index
    @global_suppliers = GlobalSupplier
                        .includes(:source_business, :suppliers, :global_supplier_products)
                        .order(Arel.sql("LOWER(global_suppliers.name) ASC"))
  end

  def show
    load_global_supplier_products
  end

  def edit
  end

  def update
    if @global_supplier.update(global_supplier_params)
      GlobalCatalog::SyncGlobalSupplierService.new(@global_supplier).call
      sync_global_supplier_products!
      redirect_to global_supplier_path(@global_supplier), notice: "Proveedor global actualizado y sincronizado."
    else
      if product_associations_update?
        set_tasa_dolar_bcv
        load_global_supplier_products
        render :show, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
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
      global_supplier_products_attributes: %i[
        id
        global_product_id
        costo_mayor
        cantidad
        costo_menor
        _destroy
      ],
    )
  end

  def set_tasa_dolar_bcv
    @tasa_dolar_bcv = TasaCambio.latest_value('Dolar BCV').to_d
  end

  def load_global_supplier_products
    @global_supplier_products_ordered = @global_supplier.global_supplier_products
                                                       .joins(:global_product)
                                                       .includes(:global_product)
                                                       .order(Arel.sql("LOWER(global_products.name) ASC"))
  end

  def product_associations_update?
    params.dig(:global_supplier, :global_supplier_products_attributes).present?
  end

  def sync_global_supplier_products!
    @global_supplier.global_supplier_products.find_each do |row|
      GlobalCatalog::SyncGlobalSupplierProductService.new(row).call
    end
  end
end
