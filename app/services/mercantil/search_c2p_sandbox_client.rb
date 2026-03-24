require 'base64'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'

module Mercantil
  class SearchC2pSandboxClient
    ENDPOINT = 'https://apimbu.mercantilbanco.com/mercantil-banco/sandbox/v1/mobile-payment/search'.freeze
    REQUIRED_CONFIG_KEYS = %i[merchant_id integrator_id terminal_id client_id secret_key origin_phone_number].freeze

    def initialize(config = default_config)
      @config = config.symbolize_keys
    end

    def search(amount:, customer_phone_number:, payment_reference:, transaction_date:)
      validate_config!

      payload = build_payload(
        amount: amount,
        customer_phone_number: customer_phone_number,
        payment_reference: payment_reference,
        transaction_date: transaction_date
      )

      response = perform_request(payload)

      {
        ok: response.code.to_i.between?(200, 299),
        status: response.code.to_i,
        request_payload: payload,
        response_body: parse_json(response.body),
        raw_response: response.body,
        error: nil
      }
    rescue StandardError => e
      {
        ok: false,
        status: nil,
        request_payload: payload,
        response_body: nil,
        raw_response: nil,
        error: e.message
      }
    end

    private

    def default_config
      {
        merchant_id: ENV['MERCANTIL_C2P_MERCHANT_ID'].presence || ENV['MERCHANTID'],
        integrator_id: ENV['MERCANTIL_C2P_INTEGRATOR_ID'].presence || ENV['INTEGRATORID'],
        terminal_id: ENV['MERCANTIL_C2P_TERMINAL_ID'].presence || ENV['TERMINALID'],
        client_id: ENV['MERCANTIL_C2P_CLIENT_ID'].presence || ENV['CLIENTID'],
        secret_key: ENV['MERCANTIL_C2P_SECRET_KEY'].presence || ENV['SECRETKEY'],
        origin_phone_number: ENV['MERCANTIL_C2P_ORIGIN_PHONE'].presence || ENV['PHONE_NUMBER']
      }
    end

    def validate_config!
      missing = REQUIRED_CONFIG_KEYS.select { |key| @config[key].blank? }
      return if missing.empty?

      raise ArgumentError, "Faltan credenciales/configuracion: #{missing.join(', ')}"
    end

    def build_payload(amount:, customer_phone_number:, payment_reference:, transaction_date:)
      {
        merchant_identify: {
          integratorId: @config[:integrator_id].to_s,
          merchantId: @config[:merchant_id].to_s,
          terminalId: @config[:terminal_id].to_s
        },
        client_identify: {
          ipaddress: '127.0.0.1',
          browser_agent: 'Ruby Net::HTTP',
          mobile: {
            manufacturer: 'Ruby'
          }
        },
        search_by: {
          amount: amount.to_s,
          currency: 'ves',
          destination_mobile_number: encrypt_value(customer_phone_number),
          origin_mobile_number: encrypt_value(@config[:origin_phone_number]),
          payment_reference: payment_reference.to_s,
          trx_date: transaction_date.to_s
        }
      }
    end

    def perform_request(payload)
      uri = URI.parse(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['X-IBM-Client-ID'] = @config[:client_id].to_s
      request.body = payload.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 12
      http.read_timeout = 20

      http.request(request)
    end

    def encrypt_value(raw_value)
      secret_key = @config[:secret_key].to_s
      normalized = raw_value.to_s

      key = Digest::SHA256.digest(secret_key).byteslice(0, 16)
      cipher = OpenSSL::Cipher.new('AES-128-ECB')
      cipher.encrypt
      cipher.key = key
      cipher.padding = 1

      encrypted = cipher.update(normalized) + cipher.final
      Base64.strict_encode64(encrypted)
    end

    def parse_json(raw_body)
      JSON.parse(raw_body)
    rescue JSON::ParserError
      { 'raw' => raw_body.to_s }
    end
  end
end
