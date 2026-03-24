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
puts "== Cargando datos de prueba para desarrollo =="

business = Business.find_or_create_by!(name: "Negocio Demo")

cat1 = Categoria.find_or_create_by!(nombre: "Electrónica", business: business)
cat2 = Categoria.find_or_create_by!(nombre: "Papelería", business: business)

10.times do |i|
	Producto.find_or_create_by!(descripcion: "Producto #{i+1}", business: business, categoria: [cat1, cat2].sample) do |p|
		p.precio_venta_usd = rand(5..100)
		p.porcentaje_ganancia = rand(10..50)
		p.exento = [true, false].sample
	end
end

ss1 = SystemService.find_or_create_by!(name: "INTT")
ss2 = SystemService.find_or_create_by!(name: "CNE")

10.times do |i|
	Service.find_or_create_by!(description: "Servicio #{i+1}", business: business) do |s|
		s.sale_price = rand(10..200)
		s.value_units = rand(1..10)
		s.available = [true, false].sample
		s.caution_service = [true, false].sample
		s.restricted_service = [true, false].sample
		s.system_service = [ss1, ss2].sample
		s.pricing_mode = %w[fixed to_agree].sample
	end
end

puts "== Datos de prueba cargados exitosamente =="
