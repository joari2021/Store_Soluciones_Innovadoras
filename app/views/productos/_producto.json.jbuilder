json.extract! producto, :id, :descripcion, :precio_costo, :precio_venta_usd, :precio_venta_bs, :cant_unidades, :foto, :nivel_ganancia, :created_at, :updated_at
json.url producto_url(producto, format: :json)
json.foto url_for(producto.foto)
