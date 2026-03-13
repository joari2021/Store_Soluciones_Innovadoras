class ClientesController < ApplicationController
  before_action :require_business
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
          document: client.document_label
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
            document: @cliente.document_label
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
    if @cliente.update(cliente_params)
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
    params.require(:cliente).permit(:document_type, :document_number, :name, :phone, :address)
  end
end
