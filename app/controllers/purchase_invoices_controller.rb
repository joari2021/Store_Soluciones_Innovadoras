class PurchaseInvoicesController < ApplicationController
  before_action :require_business
  before_action :set_purchase_invoice, only: %i[show edit update]
  before_action :load_suppliers, only: %i[new edit create update]

  def index
    @purchase_invoices = current_business.purchase_invoices.includes(:supplier).order(created_at: :desc)
  end

  def show
    @highlight_from_lot = params[:source].to_s == 'lot'
    @highlighted_item_id = if @highlight_from_lot && params[:highlighted_item_id].present?
                             parsed_id = params[:highlighted_item_id].to_i
                             parsed_id.positive? ? parsed_id : nil
                           end
  end

  def new
    caracas_now = Time.current.in_time_zone('America/Caracas')
    tasa_hoy_bcv = TasaCambio.find_by(description: 'Dolar BCV', fecha_referencia: caracas_now.to_date)&.valor

    @purchase_invoice = current_business.purchase_invoices.new(
      fecha_emision: caracas_now.to_date,
      tasa_dolar: tasa_hoy_bcv
    )
    # render view with turbo_frame_tag so the response includes the expected frame
    # the corresponding template (new.html.erb) already wraps content in
    # <turbo-frame id="modal-facturas">...
    render :new
  end

  def create
    @purchase_invoice = current_business.purchase_invoices.new(purchase_invoice_params)
    if @purchase_invoice.save
      redirect_to purchase_invoices_path, notice: 'Factura creada correctamente'
    else
      render :new
    end
  end

  def edit
    @purchase_invoice.purchase_invoice_items.build if @purchase_invoice.purchase_invoice_items.empty?
  end

  def update
    if @purchase_invoice.update(purchase_invoice_params)
      redirect_to purchase_invoices_path, notice: 'Factura actualizada'
    else
      render :edit
    end
  end

  private

  def set_purchase_invoice
    @purchase_invoice = current_business.purchase_invoices.find(params[:id])
  end

  def load_suppliers
    @available_suppliers = current_business.suppliers.order(:nombre)
  end

  def purchase_invoice_params
    params.require(:purchase_invoice).permit(
      :supplier_id,
      :fecha_emision,
      :tasa_dolar,
      :numero,
      :observaciones,
      purchase_invoice_items_attributes: %i[
        id
        producto_id
        product_name
        costo_mayor
        costo_mayor_bs
        cantidad
        costo_menor
        unid_x_pack
        subtotal
        exento
        variation_breakdown
        _destroy
      ]
    )
  end
end
