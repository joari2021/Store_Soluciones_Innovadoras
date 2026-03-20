class SuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_supplier, only: %i[show edit update destroy overwrite_product_values]
  before_action :set_tasa_dolar_bcv, only: %i[show update]

  def index
    @suppliers = current_business.suppliers.order(nombre: :asc)
  end

  def show
    @supplier_products_ordered = @supplier.supplier_products
                                          .preload(:producto)
                                          .to_a
                                          .sort_by { |row| row.producto&.descripcion.to_s.downcase }
  end

  def new
    @supplier = current_business.suppliers.new
  end

  def create
    @supplier = current_business.suppliers.new(supplier_params)
    if @supplier.save
      redirect_to suppliers_path, notice: 'Proveedor creado'
    else
      render :new
    end
  end

  def edit; end

  def update
    if @supplier.update(supplier_params)
      redirect_to supplier_path(@supplier), notice: 'Proveedor actualizado'
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @supplier.destroy
    redirect_to suppliers_path, notice: 'Proveedor eliminado'
  end

  def overwrite_product_values
    producto_id = params[:producto_id].to_s.strip
    supplier_product = @supplier.supplier_products.find_by(producto_id: producto_id)

    unless supplier_product
      render json: { error: 'No se encontró la asociación producto-proveedor.' }, status: :not_found
      return
    end

    attrs = {
      costo_mayor: params[:costo_mayor],
      cantidad: params[:cantidad],
      costo_menor: params[:costo_menor]
    }

    if supplier_product.update(attrs)
      render json: {
        ok: true,
        costo_mayor: supplier_product.costo_mayor,
        cantidad: supplier_product.cantidad,
        costo_menor: supplier_product.costo_menor
      }
    else
      render json: { error: supplier_product.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def set_supplier
    @supplier = current_business.suppliers.find(params[:id])
  end

  def supplier_params
    params.require(:supplier).permit(
      :nombre,
      :rif,
      :telefono,
      :telefono_pago_movil,
      :email,
      :direccion,
      :nro_cuenta,
      :pricing_currency_priority,
      :default_exento,
      supplier_products_attributes: %i[
        id
        producto_id
        costo_mayor
        cantidad
        costo_menor
        _destroy
      ]
    )
  end

  def set_tasa_dolar_bcv
    latest_bcv = TasaCambio.latest_for('Dolar BCV')
    @tasa_dolar_bcv = latest_bcv&.valor.to_f
    @tasa_dolar_bcv_symbol = latest_bcv&.symbol.presence || 'Bs'
    @tasa_dolar_bcv_fecha = latest_bcv&.fecha_referencia
  end
end
