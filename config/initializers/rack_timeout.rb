# Freeze long-running requests before Heroku router timeout (30s)
# to avoid thread starvation and cascading H12/H13/H18 errors.
if Rails.env.production?
  ENV['RACK_TIMEOUT_SERVICE_TIMEOUT'] ||= '20'
  ENV['RACK_TIMEOUT_WAIT_TIMEOUT'] ||= '10'
end
