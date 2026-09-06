class SystemController < ApplicationController
  before_action :require_business

  def status
    render json: {
      signature: system_data_signature,
      release: ENV['HEROKU_RELEASE_VERSION'].presence || ENV['GIT_COMMIT'].presence || 'development',
      updated_at: latest_system_update_at&.iso8601,
    }
  end

  private

  def system_data_signature
    [
      ENV['HEROKU_RELEASE_VERSION'].presence || ENV['GIT_COMMIT'].presence || 'development',
      latest_system_update_at&.utc&.iso8601(6),
      TasaCambio.maximum(:updated_at)&.utc&.iso8601(6),
    ].join('|')
  end

  def latest_system_update_at
    timestamps = [
      current_business.productos.maximum(:updated_at),
      current_business.services.maximum(:updated_at),
    ].compact

    timestamps.max
  end
end
