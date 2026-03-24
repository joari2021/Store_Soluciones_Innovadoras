class ProductosController < ApplicationController
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :require_admin, except: %i[index show]

  def index
    @productos = Producto.all.order(descripcion: :asc)
    # @productos = Producto.all.with_attached_poster
    availability_sql = Producto.availability_true_sql

    @productos = @productos.whose_name_starts_with(params[:query_text]) if params[:query_text].present?

    # Mapeo de nivel_ganancia a valores numéricos
    @nivel_ganancia_map = {
      'Baja' => 15,
      'Justa' => 23,
      'Media' => 30,
      'Alta' => 50
    }
    # Filtrar productos con alerta de precio si el filtro está activado
    if params[:filter] == 'alerta'
      @productos = @productos.where(
        "(#{availability_sql} AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 15
          WHEN 'Justa' THEN 23
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) OR
         (#{availability_sql} AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
          WHEN 'Baja' THEN 15
          WHEN 'Justa' THEN 23
          WHEN 'Media' THEN 30
          WHEN 'Alta' THEN 50
        END AS float) / 100)) * #{@tasa_dolar_bcv})"
      )
    end

    # Contar el total de productos con alerta (sin importar el filtro)
    @total_alertas = Producto.where(
      "(#{availability_sql} AND moneda_base_precio = 'Dolar' AND precio_venta_usd < (precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
        WHEN 'Baja' THEN 15
        WHEN 'Justa' THEN 23
        WHEN 'Media' THEN 30
        WHEN 'Alta' THEN 50
      END AS float) / 100)) OR
       (#{availability_sql} AND moneda_base_precio = 'Bolivar' AND precio_venta_bs < ((precio_costo / cant_unidades) / (1 - CAST(CASE nivel_ganancia
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
      redirect_to productos_path, notice: 'Producto creado exitosamente.'
    else
      render :new
    end
  end

  def show; end

  def export_excel
    productos = Producto.order(descripcion: :asc)

    headers = [
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

    table_head = headers.map { |header| "<th>#{sanitize_excel_cell(header)}</th>" }.join
    table_body = productos.map do |producto|
      values = [
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

      cells = values.map { |value| "<td>#{sanitize_excel_cell(value)}</td>" }.join
      "<tr>#{cells}</tr>"
    end.join

    rows = <<~HTML
      <html>
        <head>
          <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        </head>
        <body>
          <table border="1">
            <thead>
              <tr>#{table_head}</tr>
            </thead>
            <tbody>
              #{table_body}
            </tbody>
          </table>
        </body>
      </html>
    HTML

    filename = "productos_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xls"
    send_data rows,
              filename: filename,
              type: 'application/vnd.ms-excel; charset=utf-8',
              disposition: 'attachment'
  end

  def edit
  end

  def update
    if @producto.update(producto_params)
      redirect_to productos_path, notice: 'Producto actualizado exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @producto.destroy
      redirect_to productos_path, notice: 'Producto eliminado exitosamente.'
    else
      redirect_to productos_path, alert: 'No se pudo eliminar el producto.'
    end
  end

  private

  def sanitize_excel_cell(value)
    ERB::Util.html_escape(value.to_s.gsub(/[\r\n]/, ' ').strip)
  end

  def set_producto
    @producto = Producto.find(params[:id])
  end

  def producto_params
    permitted = params.require(:producto).permit(
      :descripcion,
      :precio_costo,
      :precio_venta_usd,
      :precio_venta_bs,
      :cant_unidades,
      :foto,
      :nivel_ganancia,
      :min_stock,
      :max_stock,
      :moneda_base_precio,
      :available,
      :disponible
    )

    if permitted.key?(:available) && !Producto.column_names.include?('available')
      permitted[:disponible] = permitted.delete(:available)
    elsif permitted.key?(:disponible) && !Producto.column_names.include?('disponible')
      permitted[:available] = permitted.delete(:disponible)
    end

    permitted
  end
end
