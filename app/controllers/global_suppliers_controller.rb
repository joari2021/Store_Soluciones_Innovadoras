class GlobalSuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_global_supplier, only: %i[show edit update overwrite_product_values]
  before_action :set_tasa_dolar_bcv, only: %i[show]

  def index
    @global_suppliers = GlobalSupplier
                        .includes(:source_business, :suppliers, :global_supplier_products)
                        .order(Arel.sql("LOWER(global_suppliers.name) ASC"))
  end

  def show
    load_global_supplier_products
  end

  def new
    @global_supplier = GlobalSupplier.new(
      pricing_currency_priority: "usd",
      active: true,
      source_business: current_business,
    )
  end

  def create
    @global_supplier = GlobalSupplier.new(global_supplier_params)
    @global_supplier.source_business ||= current_business

    if @global_supplier.save
      enforce_default_exento_on_associations!(@global_supplier)
      redirect_to global_supplier_path(@global_supplier), notice: "Proveedor global creado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @global_supplier.update(global_supplier_params)
      enforce_default_exento_on_associations!(@global_supplier)
      redirect_to global_supplier_path(@global_supplier), notice: "Proveedor global actualizado."
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

  def overwrite_product_values
    producto = current_business.productos.find_by(id: params[:producto_id])
    if producto.blank? || producto.global_product_id.blank?
      render json: { error: 'El producto local no está mapeado a un producto global.' }, status: :unprocessable_entity
      return
    end

    row = GlobalSupplierProduct.find_or_initialize_by(
      global_supplier_id: @global_supplier.id,
      global_product_id: producto.global_product_id,
    )

    resolved_exento = if params.key?(:exento)
        ActiveModel::Type::Boolean.new.cast(params[:exento])
      elsif row.new_record?
        @global_supplier.default_exento?
      else
        row.exento?
      end
    resolved_exento = true if @global_supplier.default_exento?

    row.assign_attributes(
      costo_mayor: params[:costo_mayor],
      cantidad: params[:cantidad],
      costo_menor: params[:costo_menor],
      exento: resolved_exento,
      active: true,
    )

    if row.save
      render json: {
        ok: true,
        costo_mayor: row.costo_mayor,
        cantidad: row.cantidad,
        costo_menor: row.costo_menor,
        exento: row.exento,
      }
    else
      render json: { error: row.errors.full_messages.to_sentence }, status: :unprocessable_entity
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
        exento
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

  def enforce_default_exento_on_associations!(supplier)
    return unless supplier.default_exento?

    supplier.global_supplier_products.update_all(exento: true)
  end
end
