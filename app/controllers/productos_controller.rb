class ProductosController < ApplicationController
  before_action :set_producto, only: %i[show edit update destroy]

  def index
    @productos = Producto.all.order(descripcion: :asc)
    #@productos = Producto.all.with_attached_poster

    if params[:query_text].present?
      @productos = @productos.whose_name_starts_with(params[:query_text])
    end
  end

  def new
    @producto = Producto.new
  end

  def create
    @producto = Producto.new(producto_params)
    if @producto.save
      redirect_to productos_path, notice: "Producto creado exitosamente."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @producto.update(producto_params)
      redirect_to productos_path, notice: "Producto actualizado exitosamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @producto.destroy
      redirect_to productos_path, notice: "Producto eliminado exitosamente."
    else
      redirect_to productos_path, alert: "No se pudo eliminar el producto."
    end
  end

  private

  def set_producto
    @producto = Producto.find(params[:id])
  end

  def producto_params
    params.require(:producto).permit(:descripcion, :precio_costo, :precio_venta_usd, :precio_venta_bs, :cant_unidades, :foto, :nivel_ganancia, :min_stock, :max_stock, :moneda_base_precio)
  end
end
