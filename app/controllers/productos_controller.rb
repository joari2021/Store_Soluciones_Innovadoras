class ProductosController < ApplicationController
  before_action :require_business
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :require_admin, except: %i[index show search]

  def index
    @productos = current_business.productos
                                 .includes(:product_variations, stock_lots: [{ stock_lot_variations: :product_variation },
                                                                             { purchase_invoice_item: :purchase_invoice }])
                                 .order(descripcion: :asc)
    # @productos = Producto.all.with_attached_poster

    @productos = @productos.whose_name_starts_with(params[:query_text]) if params[:query_text].present?

    @pagy, @productos = pagy_countless(@productos, items: 48)
  end

  def search
    query = params[:q].to_s.strip
    supplier_id = params[:supplier_id].to_s.strip

    productos = if query.present?
                  current_business.productos.whose_name_starts_with(query)
                else
                  Producto.none
                end

    if supplier_id.present?
      supplier = current_business.suppliers.find_by(id: supplier_id)
      return render json: [] unless supplier

      rows = productos
             .joins(:supplier_products)
             .includes(:product_variations)
             .where(supplier_products: { supplier_id: supplier.id })
             .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
             .limit(10)
             .select(
               :id,
               :descripcion,
               'supplier_products.costo_mayor AS supplier_costo_mayor',
               'supplier_products.costo_menor AS supplier_costo_menor',
               'supplier_products.cantidad AS supplier_unid_x_pack'
             )

      payload = rows.map do |row|
        {
          id: row.id,
          descripcion: row.descripcion,
          costo_mayor: row.attributes['supplier_costo_mayor'],
          costo_menor: row.attributes['supplier_costo_menor'],
          unid_x_pack: row.attributes['supplier_unid_x_pack'],
          variations: row.product_variations.order(:id).map do |variation|
            { id: variation.id, description: variation.description }
          end
        }
      end

      render json: payload
      return
    end

    render json: productos
      .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
      .limit(10)
      .select(:id, :descripcion)
  end

  def new
    @producto = current_business.productos.new
    @producto.product_variations.build(description: 'Unica')
  end

  def create
    @producto = current_business.productos.new(producto_params)
    if @producto.save
      if request.headers['Turbo-Frame'].present?
        # Render turbo_stream that appends the new row into the index tbody and clears the modal frame
        append_stream = view_context.turbo_stream.append('productos_tbody', partial: 'producto_row',
                                                                            locals: { producto: @producto })
        clear_frame = view_context.turbo_stream.update('modal-productos', '')
        render turbo_stream: [append_stream, clear_frame]
      else
        redirect_to productos_path, notice: 'Producto creado exitosamente.'
      end
    elsif request.headers['Turbo-Frame'].present?
      frame_html = view_context.turbo_frame_tag('modal-productos') do
        view_context.render(partial: 'form', locals: { producto: @producto })
      end
      render html: frame_html.html_safe, status: :unprocessable_entity, layout: false
    # Render the form partial wrapped in the turbo-frame so Turbo can replace the frame content
    else
      render :new
    end
  end

  def show; end

  def edit
    return unless @producto.product_variations.empty?

    @producto.product_variations.build(description: 'Unica')
  end

  def update
    if @producto.update(producto_params)
      redirect_to productos_path, notice: 'Producto actualizado exitosamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @producto.destroy
      redirect_to productos_path, notice: 'Producto eliminado exitosamente.'
    else
      redirect_to productos_path, alert: 'No se pudo eliminar el producto.'
    end
  end

  private

  def set_producto
    @producto = current_business.productos.find(params[:id])
  end

  def producto_params
    params.require(:producto).permit(
      :descripcion,
      :precio_venta_usd,
      :foto,
      :porcentaje_ganancia,
      product_variations_attributes: %i[id description safety_stock _destroy]
    )
  end
end
