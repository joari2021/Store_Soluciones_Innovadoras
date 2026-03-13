class ChangeDecimalScalesToTwo < ActiveRecord::Migration[7.1]
  def up
    change_column :factura_items, :costo_mayor, :decimal, precision: 12, scale: 2, using: 'ROUND(costo_mayor, 2)'
    change_column :factura_items, :cantidad, :decimal, precision: 12, scale: 2, using: 'ROUND(cantidad, 2)'
    change_column :factura_items, :costo_menor, :decimal, precision: 12, scale: 2, using: 'ROUND(costo_menor, 2)'
    change_column :factura_items, :unid_x_pack, :decimal, precision: 12, scale: 2, using: 'ROUND(unid_x_pack, 2)'
    change_column :factura_items, :subtotal, :decimal, precision: 14, scale: 2, using: 'ROUND(subtotal, 2)'
    change_column :factura_items, :costo_mayor_bs, :decimal, precision: 14, scale: 2, using: 'ROUND(costo_mayor_bs, 2)'

    change_column :facturas, :tasa_dolar, :decimal, precision: 12, scale: 2, using: 'ROUND(tasa_dolar, 2)'
    change_column :facturas, :monto_total, :decimal, precision: 14, scale: 2, using: 'ROUND(monto_total, 2)'

    change_column :peliculas, :promedio_ranking, :decimal, precision: 12, scale: 2, using: 'ROUND(promedio_ranking::numeric, 2)'

    change_column :rankings, :valor, :decimal, precision: 12, scale: 2, using: 'ROUND(valor::numeric, 2)'

    change_column :service_managers, :cost, :decimal, precision: 12, scale: 2, using: 'ROUND(cost::numeric, 2)'

    change_column :services, :value_units, :decimal, precision: 12, scale: 2, using: 'ROUND(value_units::numeric, 2)'
    change_column :services, :sale_price, :decimal, precision: 12, scale: 2, using: 'ROUND(sale_price::numeric, 2)'

    change_column :product_variations, :safety_stock, :decimal, precision: 12, scale: 2, using: 'ROUND(safety_stock, 2)'

    change_column :productos, :precio_venta_usd, :decimal, precision: 14, scale: 2, using: 'ROUND(precio_venta_usd, 2)'

    change_column :stock_lot_variations, :quantity_in, :decimal, precision: 12, scale: 2, using: 'ROUND(quantity_in, 2)'
    change_column :stock_lot_variations, :quantity_remaining, :decimal, precision: 12, scale: 2, using: 'ROUND(quantity_remaining, 2)'

    change_column :stock_lots, :unit_cost_usd, :decimal, precision: 12, scale: 2, using: 'ROUND(unit_cost_usd, 2)'
    change_column :stock_lots, :quantity_in, :decimal, precision: 12, scale: 2, using: 'ROUND(quantity_in, 2)'
    change_column :stock_lots, :quantity_remaining, :decimal, precision: 12, scale: 2, using: 'ROUND(quantity_remaining, 2)'

    change_column :supplier_products, :costo_mayor, :decimal, precision: 12, scale: 2, using: 'ROUND(costo_mayor, 2)'
    change_column :supplier_products, :cantidad, :decimal, precision: 12, scale: 2, using: 'ROUND(cantidad, 2)'
    change_column :supplier_products, :costo_menor, :decimal, precision: 12, scale: 2, using: 'ROUND(costo_menor, 2)'

    change_column :tasa_cambios, :valor, :decimal, precision: 12, scale: 2, using: 'ROUND(valor, 2)'

    change_column :venta_items, :quantity, :decimal, precision: 12, scale: 2, using: 'ROUND(quantity, 2)'
    change_column :venta_items, :unit_price_usd, :decimal, precision: 14, scale: 2, using: 'ROUND(unit_price_usd, 2)'
    change_column :venta_items, :subtotal_usd, :decimal, precision: 14, scale: 2, using: 'ROUND(subtotal_usd, 2)'

    change_column :ventas, :tasa_dolar, :decimal, precision: 12, scale: 2, using: 'ROUND(tasa_dolar, 2)'
    change_column :ventas, :vat_rate, :decimal, precision: 5, scale: 2, using: 'ROUND(vat_rate, 2)'
  end

  def down
    change_column :factura_items, :costo_mayor, :decimal, precision: 12, scale: 4
    change_column :factura_items, :cantidad, :decimal, precision: 12, scale: 4
    change_column :factura_items, :costo_menor, :decimal, precision: 12, scale: 4
    change_column :factura_items, :unid_x_pack, :decimal, precision: 12, scale: 4
    change_column :factura_items, :subtotal, :decimal, precision: 14, scale: 4
    change_column :factura_items, :costo_mayor_bs, :decimal, precision: 14, scale: 4

    change_column :facturas, :tasa_dolar, :decimal, precision: 12, scale: 4
    change_column :facturas, :monto_total, :decimal, precision: 14, scale: 4

    change_column :peliculas, :promedio_ranking, :float

    change_column :rankings, :valor, :float

    change_column :service_managers, :cost, :float

    change_column :services, :value_units, :float
    change_column :services, :sale_price, :float

    change_column :product_variations, :safety_stock, :decimal, precision: 12, scale: 4

    change_column :productos, :precio_venta_usd, :decimal

    change_column :stock_lot_variations, :quantity_in, :decimal, precision: 12, scale: 4
    change_column :stock_lot_variations, :quantity_remaining, :decimal, precision: 12, scale: 4

    change_column :stock_lots, :unit_cost_usd, :decimal, precision: 12, scale: 4
    change_column :stock_lots, :quantity_in, :decimal, precision: 12, scale: 4
    change_column :stock_lots, :quantity_remaining, :decimal, precision: 12, scale: 4

    change_column :supplier_products, :costo_mayor, :decimal, precision: 12, scale: 4
    change_column :supplier_products, :cantidad, :decimal, precision: 12, scale: 4
    change_column :supplier_products, :costo_menor, :decimal, precision: 12, scale: 4

    change_column :tasa_cambios, :valor, :decimal

    change_column :venta_items, :quantity, :decimal, precision: 12, scale: 4
    change_column :venta_items, :unit_price_usd, :decimal, precision: 14, scale: 4
    change_column :venta_items, :subtotal_usd, :decimal, precision: 14, scale: 4

    change_column :ventas, :tasa_dolar, :decimal, precision: 12, scale: 4
    change_column :ventas, :vat_rate, :decimal, precision: 5, scale: 4
  end
end
