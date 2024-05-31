json.extract! serie_tv, :id, :poster, :name, :others_title, :year, :temporadas, :capitulos, :director, :reparto, :sinopsis, :audio, :calidad, :status, :formato_video, :codigo, :created_at, :updated_at
json.url serie_tv_url(serie_tv, format: :json)
