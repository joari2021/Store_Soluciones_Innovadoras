class SuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :load_local_global_product_ids
  before_action :set_supplier, only: %i[show edit update overwrite_product_values]
  before_action :set_tasa_dolar_bcv, only: %i[show update]

  def index
    @suppliers = filtered_global_suppliers
                 .includes(:source_business, :suppliers, :global_supplier_products)
                 .order(Arel.sql('LOWER(global_suppliers.name) ASC'))
  end

  def show
    load_global_supplier_products
  end

  def new
    redirect_to suppliers_path, alert: 'La creación local de proveedores está deshabilitada. Usa proveedores filtrados por negocio.'
  end

  def create
    redirect_to suppliers_path, alert: 'La creación local de proveedores está deshabilitada.'
  end

  def edit; end

  def update
    if @supplier.update(global_supplier_params)
      redirect_to supplier_path(@supplier), notice: 'Proveedor actualizado.'
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

  def destroy
    redirect_to suppliers_path, alert: 'La eliminación local de proveedores está deshabilitada.'
  end

  def overwrite_product_values
    producto = current_business.productos.find_by(id: params[:producto_id])
    if producto.blank? || producto.global_product_id.blank?
      render json: { error: 'El producto local no está mapeado a un producto global.' }, status: :unprocessable_entity
      return
    end

    unless @local_global_product_ids.include?(producto.global_product_id)
      render json: { error: 'El producto no pertenece al catálogo local del negocio actual.' }, status: :unprocessable_entity
      return
    end

    row = GlobalSupplierProduct.find_or_initialize_by(
      global_supplier_id: @supplier.id,
      global_product_id: producto.global_product_id,
    )

    row.assign_attributes(
      costo_mayor: params[:costo_mayor],
      cantidad: params[:cantidad],
      costo_menor: params[:costo_menor],
      active: true,
    )

    if row.save
      render json: {
        ok: true,
        costo_mayor: row.costo_mayor,
        cantidad: row.cantidad,
        costo_menor: row.costo_menor,
      }
    else
      render json: { error: row.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def search_products
    query = params[:q].to_s.strip
    render json: [] and return if query.length < 2
    render json: [] and return if @local_global_product_ids.empty?

    products = GlobalProduct
               .where(id: @local_global_product_ids)
               .where('global_products.name ILIKE ?', "%#{query}%")
               .order(Arel.sql('LOWER(global_products.name) ASC'))
               .limit(20)

    render json: products.map { |product| { id: product.id, name: product.name, display_name: product.display_name_with_presentation } }
  end

  private

  def load_local_global_product_ids
    @local_global_product_ids = current_business.productos.where.not(global_product_id: nil).distinct.pluck(:global_product_id)
  end

  def filtered_global_suppliers
    return GlobalSupplier.none if @local_global_product_ids.empty?

    GlobalSupplier
      .joins(:global_supplier_products)
      .where(global_supplier_products: { global_product_id: @local_global_product_ids })
      .distinct
  end

  def set_supplier
    @supplier = filtered_global_suppliers.find(params[:id])
  end

  def global_supplier_params
    attrs = params.require(:global_supplier).permit(
      :name,
      :rif,
      :phone,
      :mobile_payment_phone,
      :email,
      :address,
      :bank_account_number,
      :pricing_currency_priority,
      :default_exento,
      global_supplier_products_attributes: %i[
        id
        global_product_id
        costo_mayor
        cantidad
        costo_menor
        _destroy
      ]
    )

    nested = attrs[:global_supplier_products_attributes]
    return attrs if nested.blank?

    allowed = @local_global_product_ids.map(&:to_s)
    filtered_nested = nested.to_h.select do |_idx, payload|
      product_id = payload[:global_product_id].to_s
      id = payload[:id].to_s
      next true if id.present?

      allowed.include?(product_id)
    end

    attrs[:global_supplier_products_attributes] = filtered_nested
    attrs
  end

  def set_tasa_dolar_bcv
    @tasa_dolar_bcv = TasaCambio.latest_value('Dolar BCV').to_d
  end

  def load_global_supplier_products
    @global_supplier_products_ordered = @supplier.global_supplier_products
                                               .joins(:global_product)
                                               .where(global_supplier_products: { global_product_id: @local_global_product_ids })
                                               .includes(:global_product)
                                               .order(Arel.sql('LOWER(global_products.name) ASC'))
  end

  def product_associations_update?
    params.dig(:global_supplier, :global_supplier_products_attributes).present?
  end
end
