# Timeout de rack-timeout desactivado por defecto.
# Para activarlo en produccion, definir ENABLE_RACK_TIMEOUT=1.
if Rails.env.production? && ENV['ENABLE_RACK_TIMEOUT'].to_s == '1'
  ENV['RACK_TIMEOUT_SERVICE_TIMEOUT'] ||= '20'
  ENV['RACK_TIMEOUT_WAIT_TIMEOUT'] ||= '10'
end
