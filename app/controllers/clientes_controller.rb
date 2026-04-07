class ClientesController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:clientes) }
  before_action :require_admin, only: %i[destroy]
  before_action :set_cliente, only: %i[show edit update destroy]

  def index
    @clientes = current_business.clientes.order(:name)
    @pagy, @clientes = pagy_countless(@clientes, items: 24)
  end

  def show
    @ventas = @cliente.ventas.includes(:venta_items).order(created_at: :desc)
  end

  def new
    @cliente = current_business.clientes.new(document_type: 'V')
  end

  def search
    query = params[:q].to_s.strip
    return render json: { clients: [] } if query.length < 1

    clients = current_business.clientes
                              .where(
                                'name ILIKE :q OR document_number ILIKE :q',
                                q: "%#{query}%"
                              )
                              .order(:name)
                              .limit(10)

    render json: {
      clients: clients.map do |client|
        {
          id: client.id,
          name: client.name,
          document: client.document_label,
          phone: client.phone.to_s,
          has_benefits: client.has_special_benefits?,
          benefits: client.normalized_benefits_config,
        }
      end
    }
  end

  def create
    @cliente = current_business.clientes.new(cliente_params)

    respond_to do |format|
      if @cliente.save
        format.html { redirect_to cliente_path(@cliente), notice: 'Cliente creado correctamente.' }
        format.json do
          render json: {
            id: @cliente.id,
            name: @cliente.name,
            document: @cliente.document_label,
            phone: @cliente.phone.to_s,
            has_benefits: @cliente.has_special_benefits?,
            benefits: @cliente.normalized_benefits_config,
          }, status: :created
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { error: @cliente.errors.full_messages.to_sentence }, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    if @cliente.update(cliente_update_params)
      redirect_to cliente_path(@cliente), notice: 'Cliente actualizado correctamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @cliente.destroy
    redirect_to clientes_path, notice: 'Cliente eliminado.'
  end

  private

  def set_cliente
    @cliente = current_business.clientes.find(params[:id])
  end

  def cliente_params
    permitted = params.require(:cliente).permit(
      :document_type,
      :document_number,
      :name,
      :phone,
      :address,
      :benefits_config_json,
      :general_product_discount_percent,
      product_rules_rows: %i[product_id mode value],
      service_fixed_price_rows: %i[service_id value],
    )
    build_cliente_attributes(permitted)
  end

  def cliente_update_params
    return cliente_params if current_user_admin?

    params.require(:cliente).permit(:phone, :address)
  end

  def build_cliente_attributes(permitted)
    attrs = permitted.to_h
    raw_benefits_json = attrs.delete("benefits_config_json")

    benefits_config = Cliente.normalize_benefits_config(raw_benefits_json)

    general_discount = attrs.delete("general_product_discount_percent")
    if general_discount.present?
      benefits_config["general_product_discount_percent"] =
        [[general_discount.to_d, 0.to_d].max, 100.to_d].min.round(2).to_f
    end

    product_rows = Array(attrs.delete("product_rules_rows"))
    if product_rows.any?
      product_rules = {}
      product_rows.each do |row|
        next unless row.is_a?(Hash)

        product_id = row["product_id"].to_s.strip
        mode = row["mode"].to_s.strip.downcase
        value = row["value"].to_d
        next if product_id.blank?
        next unless %w[fixed percent].include?(mode)
        next unless value.positive?

        normalized_value = mode == "percent" ? [value, 100.to_d].min : value
        product_rules[product_id] = {
          "mode" => mode,
          "value" => normalized_value.round(2).to_f,
        }
      end
      benefits_config["product_rules"] = product_rules
    end

    service_rows = Array(attrs.delete("service_fixed_price_rows"))
    if service_rows.any?
      service_prices = {}
      service_rows.each do |row|
        next unless row.is_a?(Hash)

        service_id = row["service_id"].to_s.strip
        value = row["value"].to_d
        next if service_id.blank?
        next unless value.positive?

        service_prices[service_id] = value.round(2).to_f
      end
      benefits_config["service_fixed_prices"] = service_prices
    end

    attrs["benefits_config"] = Cliente.normalize_benefits_config(benefits_config)
    attrs
  end
end
