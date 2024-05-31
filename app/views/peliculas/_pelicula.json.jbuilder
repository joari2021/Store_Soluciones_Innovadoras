json.extract! pelicula, :id, :poster, :name, :others_titles, :year, :duration_hours, :duration_minutes, :director, :reparto, :sinopsis, :audio, :calidad, :formato_video, :codigo, :created_at, :updated_at
json.url pelicula_url(pelicula, format: :json)
