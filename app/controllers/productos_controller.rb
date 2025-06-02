class ProductosController < ApplicationController
  before_action :set_producto, only: %i[show edit update destroy]

  def index
    @productos = Producto.all.order(descripcion: :asc)
    #@productos = Producto.all.with_attached_poster

    if params[:query_text].present?
      @productos = @productos.whose_name_starts_with(params[:query_text])
    end
=begin
    # Filtrar productos con precios que necesitan corrección
    if params[:filter] == "alerta"
      @productos = @productos.select do |producto|
        costo_unidad = producto.precio_costo / producto.cant_unidades
        precio_sugerido_usd = producto.precio_sugerido_usd(costo_unidad)

        if producto.moneda_base_precio == "Dolar" 
          precio_sugerido_usd > producto.precio_venta_usd && Current.user&.admin? 
        else
          precio_sugerido_bs = producto.calcular_precio_bs(precio_sugerido_usd)
          precio_sugerido_bs > producto.precio_venta_bs && Current.user&.admin? 
        end
      end
    end

    # Contar el total de productos con alerta (sin importar el filtro)
    @total_alertas = Producto.all.select do |producto|
      costo_unidad = producto.precio_costo / producto.cant_unidades
      precio_sugerido_usd = producto.precio_sugerido_usd(costo_unidad)

      if producto.moneda_base_precio == "Dolar"
        precio_sugerido_usd > producto.precio_venta_usd
      else
        precio_sugerido_bs = producto.calcular_precio_bs(precio_sugerido_usd)
        precio_sugerido_bs > producto.precio_venta_bs
      end
    end.size
=end
    # Mapeo de nivel_ganancia a valores numéricos
    @nivel_ganancia_map = {
      "Baja" => 20,
      "Media" => 30,
      "Alta" => 50
    }
    # Filtrar productos con alerta de precio si el filtro está activado
    if params[:filter] == "alerta"
      @productos = @productos.where(
        "(available = true AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 20
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) OR
         (available = true AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 20
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) * #{@tasa_dolar_bcv})"
      )
    end

    # Contar el total de productos con alerta (sin importar el filtro)
    @total_alertas = Producto.where(
      "(available = true AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
        WHEN 'Baja' THEN 20
        WHEN 'Media' THEN 30
        WHEN 'Alta' THEN 50
      END AS float) / 100)) OR
       (available = true AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
        WHEN 'Baja' THEN 20
        WHEN 'Media' THEN 30
        WHEN 'Alta' THEN 50
      END AS float) / 100)) * #{@tasa_dolar_bcv})"
    ).count

    @pagy, @productos = pagy_countless(@productos, items: 24)
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
    params.require(:producto).permit(:descripcion, :precio_costo, :precio_venta_usd, :precio_venta_bs, :cant_unidades, :foto, :nivel_ganancia, :min_stock, :max_stock, :moneda_base_precio, :available)
  end
end
