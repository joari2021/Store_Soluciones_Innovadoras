require 'csv'

class ProductosController < ApplicationController
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :require_admin, except: [:index, :show]

  def index
    @productos = Producto.all.order(descripcion: :asc)
    #@productos = Producto.all.with_attached_poster

    if params[:query_text].present?
      @productos = @productos.whose_name_starts_with(params[:query_text])
    end

    # Mapeo de nivel_ganancia a valores numéricos
    @nivel_ganancia_map = {
      "Baja" => 15,
      "Justa" => 23,
      "Media" => 30,
      "Alta" => 50
    }
    # Filtrar productos con alerta de precio si el filtro está activado
    if params[:filter] == "alerta"
      @productos = @productos.where(
        "(available = true AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 15
          WHEN 'Justa' THEN 23
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) OR
         (available = true AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 15
          WHEN 'Justa' THEN 23
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) * #{@tasa_dolar_bcv})"
      )
    end

    # Contar el total de productos con alerta (sin importar el filtro)
    @total_alertas = Producto.where(
      "(available = true AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
        WHEN 'Baja' THEN 15
        WHEN 'Justa' THEN 23
        WHEN 'Media' THEN 30
        WHEN 'Alta' THEN 50
      END AS float) / 100)) OR
       (available = true AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
        WHEN 'Baja' THEN 15
        WHEN 'Justa' THEN 23
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

  def show;end

  def export_excel
    productos = Producto.order(descripcion: :asc)

    rows = CSV.generate(col_sep: "\t") do |csv|
      csv << [
        'ID',
        'Descripcion',
        'Precio costo',
        'Precio venta USD',
        'Precio venta Bs',
        'Cantidad unidades',
        'Nivel ganancia',
        'Moneda base precio',
        'Min stock',
        'Max stock',
        'Disponible',
        'Creado en',
        'Actualizado en'
      ]

      productos.find_each do |producto|
        csv << [
          producto.id,
          producto.descripcion,
          producto.precio_costo,
          producto.precio_venta_usd,
          producto.precio_venta_bs,
          producto.cant_unidades,
          producto.nivel_ganancia,
          producto.moneda_base_precio,
          producto.min_stock,
          producto.max_stock,
          producto.available? ? 'Si' : 'No',
          producto.created_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S'),
          producto.updated_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S')
        ]
      end
    end

    filename = "productos_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xls"
    send_data "\uFEFF#{rows}",
              filename: filename,
              type: 'application/vnd.ms-excel; charset=utf-8',
              disposition: 'attachment'
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
