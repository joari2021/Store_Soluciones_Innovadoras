class MercantilC2pSandboxController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:services) }
  before_action :require_admin
  before_action :ensure_development_mode

  def index
    assign_default_form
  end

  def create
    assign_default_form
    @form = @form.merge(search_params.to_h.symbolize_keys)
    normalize_form!

    client = Mercantil::SearchC2pSandboxClient.new
    result = client.search(
      amount: @form[:amount],
      customer_phone_number: @form[:customer_phone_number],
      payer_id: @form[:payer_id],
      payment_reference: @form[:payment_reference],
      transaction_date: @form[:transaction_date]
    )

    @request_ok = result[:ok]
    @http_status = result[:status]
    @api_error = result[:error]
    @request_payload = result[:request_payload]
    @api_response = result[:response_body]

    render :index
  end

  private

  def assign_default_form
    @form = {
      amount: '1318144',
      customer_phone_prefix: '424',
      customer_phone_line: '1513063',
      customer_phone_number: '',
      payer_id: 'V18367443',
      payment_reference: '87860014874',
      transaction_date: '2026-03-03'
    }
    @request_ok = nil
    @http_status = nil
    @api_error = nil
    @request_payload = nil
    @api_response = nil
  end

  def search_params
    params.fetch(:mercantil_c2p_search, {}).permit(
      :amount,
      :customer_phone_prefix,
      :customer_phone_line,
      :payer_id,
      :payment_reference,
      :transaction_date
    )
  end

  def normalize_form!
    @form[:amount] = @form[:amount].to_s.strip
    @form[:customer_phone_prefix] = @form[:customer_phone_prefix].to_s.gsub(/\D/, '')
    @form[:customer_phone_line] = @form[:customer_phone_line].to_s.gsub(/\D/, '')
    @form[:customer_phone_number] = "58#{@form[:customer_phone_prefix]}#{@form[:customer_phone_line]}"
    @form[:payer_id] = @form[:payer_id].to_s.strip.upcase
    @form[:payment_reference] = @form[:payment_reference].to_s.strip
    @form[:transaction_date] = @form[:transaction_date].to_s
  end

  def ensure_development_mode
    return if Rails.env.development?

    redirect_to root_path, alert: 'Este modulo de pruebas solo esta habilitado en desarrollo.'
  end
end
