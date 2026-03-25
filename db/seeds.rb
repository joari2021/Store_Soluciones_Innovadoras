# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ==== DATOS DE PRUEBA PARA DESARROLLO ====
puts '== Cargando datos de prueba para desarrollo =='

business = Business.find_or_create_by!(name: 'Negocio Demo')

TasaCambio.find_or_create_by!(description: 'Dolar BCV', fecha_referencia: Date.current) do |tasa|
  tasa.valor = 100
  tasa.symbol = '$'
end

TasaCambio.find_or_create_by!(description: 'Unidad VI', fecha_referencia: Date.current) do |tasa|
  tasa.valor = 130
  tasa.symbol = 'Bs'
end

cat1 = Categoria.find_or_create_by!(nombre: 'Electronica', business: business)
cat2 = Categoria.find_or_create_by!(nombre: 'Papeleria', business: business)

15.times do |i|
  Producto.find_or_create_by!(descripcion: "Producto Demo #{i + 1}", business: business,
                              categoria: [cat1, cat2].sample) do |p|
    p.precio_venta_usd = rand(5..100)
    p.porcentaje_ganancia = rand(10..50)
    p.exento = [true, false].sample
  end
end

default_system_services = [
  'INTT',
  'CNE',
  'SAIME',
  'SAREN',
  'Apostilla',
  'Banco Bancamiga',
  'Banco Venezuela',
  'Impresion',
  'Plastificacion'
]

default_system_services.each do |name|
  SystemService.find_or_create_by!(name: name)
end

services_per_system = 15
system_services = SystemService.order(:name).to_a
created_services = 0

system_services.each do |system_service|
  (1..services_per_system).each do |index|
    description = format('%s Demo %02d', system_service.name, index)

    service = Service.find_or_initialize_by(
      business: business,
      system_service: system_service,
      description: description
    )

    service.assign_attributes(
      pricing_mode: 'fixed',
      currency_base_price: 'Dolar BCV',
      sale_price: (10 + index),
      available: true,
      caution_service: false,
      restricted_service: false,
      delivery_physical_enabled: false,
      delivery_digital_enabled: true,
      cost: false,
      note: 'Semilla de pruebas'
    )

    normalized_system_name = I18n.transliterate(system_service.name.to_s).downcase
    if normalized_system_name.include?('plastificacion')
      material_product = business.productos.order(:id).first
      if material_product.present?
        surcharge = service.service_print_material_surcharges.find do |row|
          row.producto_id.to_i == material_product.id
        end

        surcharge ||= service.service_print_material_surcharges.build(producto: material_product)

        surcharge.description = material_product.descripcion
        surcharge.surcharge_percent = 0
        surcharge.required_quantity = 1
        surcharge.include_product_price_in_sale = false
      end
    end

    was_new = service.new_record?
    service.save!
    created_services += 1 if was_new
  end
end

extra_distribution = [13, 8, 9]
extra_created_services = 0
rng = Random.new(business.id.to_i + 20_260_324)
selected_for_extras = system_services.sample(extra_distribution.size, random: rng)

selected_for_extras.each_with_index do |system_service, idx|
  extra_count = extra_distribution[idx]

  (1..extra_count).each do |index|
    description = format('%s Extra %02d', system_service.name, index)

    service = Service.find_or_initialize_by(
      business: business,
      system_service: system_service,
      description: description
    )

    service.assign_attributes(
      pricing_mode: 'fixed',
      currency_base_price: 'Dolar BCV',
      sale_price: (30 + index),
      available: true,
      caution_service: false,
      restricted_service: false,
      delivery_physical_enabled: false,
      delivery_digital_enabled: true,
      cost: false,
      note: 'Semilla extra aleatoria por system service'
    )

    normalized_system_name = I18n.transliterate(system_service.name.to_s).downcase
    if normalized_system_name.include?('plastificacion')
      material_product = business.productos.order(:id).first
      if material_product.present?
        surcharge = service.service_print_material_surcharges.find do |row|
          row.producto_id.to_i == material_product.id
        end

        surcharge ||= service.service_print_material_surcharges.build(producto: material_product)

        surcharge.description = material_product.descripcion
        surcharge.surcharge_percent = 0
        surcharge.required_quantity = 1
        surcharge.include_product_price_in_sale = false
      end
    end

    was_new = service.new_record?
    service.save!
    extra_created_services += 1 if was_new
  end
end

puts '== Datos de prueba cargados exitosamente =='
puts "System services detectados: #{system_services.size}"
puts "Servicios nuevos creados: #{created_services}"
puts "Servicios esperados por system service: #{services_per_system}"
puts "System services con extras (aleatorio estable): #{selected_for_extras.map(&:name).join(', ')}"
puts "Servicios extras nuevos creados: #{extra_created_services}"
puts "Distribucion extra aplicada: #{extra_distribution.join(', ')}"
