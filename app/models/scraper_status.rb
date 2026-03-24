class ScraperStatus < ApplicationRecord
  BCV_SSL_KEY = 'bcv_ssl'.freeze

  validates :key, presence: true, uniqueness: true

  def self.bcv_ssl
    find_by(key: BCV_SSL_KEY)
  end

  def self.mark_bcv_ssl_failure!(message:, occurred_at: Time.current)
    status = find_or_initialize_by(key: BCV_SSL_KEY)
    status.healthy = false
    status.last_error_message = message
    status.last_error_at = occurred_at
    status.save!
  end

  def self.mark_bcv_ssl_success!(occurred_at: Time.current)
    status = find_or_initialize_by(key: BCV_SSL_KEY)
    status.healthy = true
    status.last_success_at = occurred_at
    status.save!
  end
end
