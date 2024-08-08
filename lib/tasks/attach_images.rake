# lib/tasks/attach_images.rake
namespace :db do
  desc 'Attach images to peliculas'
  task attach_images: :environment do
    Pelicula.find_each do |pelicula|
      # Define las extensiones permitidas
      allowed_extensions = %w[jpg jpeg png webp]
      
      # Encuentra el archivo con la extensión correcta
      image_path = allowed_extensions.map do |ext|
        path = Rails.root.join("test/fixtures/files/posters_peliculas/#{pelicula.name.parameterize}.#{ext}")
        File.exist?(path) ? path : nil
      end.compact.first

      # Adjunta la imagen si se encontró
      if image_path
        pelicula.poster.attach(io: File.open(image_path), filename: File.basename(image_path))
      else
        puts "No se encontro una imagen para la pelicula #{pelicula.name}"
      end
    end
  end
end
