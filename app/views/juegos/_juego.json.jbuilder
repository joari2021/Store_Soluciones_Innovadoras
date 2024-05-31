json.extract! juego, :id, :poster, :name, :year, :desarrollador, :plataforma, :sinopsis, :audio, :calidad, :formato_video, :codigo, :created_at, :updated_at
json.url juego_url(juego, format: :json)
