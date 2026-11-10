# Freeze long-running requests before Heroku router timeout (30s)
# to avoid thread starvation and cascading H12/H13/H18 errors.
if Rails.env.production?
  Rack::Timeout.service_timeout = Integer(ENV.fetch('RACK_TIMEOUT_SERVICE_TIMEOUT', 20))
  Rack::Timeout.wait_timeout = Integer(ENV.fetch('RACK_TIMEOUT_WAIT_TIMEOUT', 10))
end
