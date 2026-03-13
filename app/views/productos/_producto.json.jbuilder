json.extract! producto, :id, :descripcion, :precio_venta_usd, :porcentaje_ganancia, :min_stock, :max_stock, :created_at, :updated_at
json.url producto_url(producto, format: :json)
json.foto url_for(producto.foto)
