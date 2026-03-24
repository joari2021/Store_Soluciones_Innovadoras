class ProductosController < ApplicationController
  PRODUCTS_PER_PAGE = 36

  before_action :require_business
  before_action -> { require_module_access!(:productos) }
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :require_admin, except: %i[index show search]

  def index
    @query_text = params[:query_text].to_s.strip
    @low_stock_filter = ActiveModel::Type::Boolean.new.cast(params[:low_stock])
    @below_target_margin_filter = ActiveModel::Type::Boolean.new.cast(params[:below_target_margin])
    @categorias = current_business.categorias.order(nombre: :asc)
    @selected_categoria = @categorias.find_by(id: params[:category_id]) if params[:category_id].present?
    @selected_categoria_id = @selected_categoria&.id
    @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
    @below_target_margin_total_count = calculate_below_target_margin_total_count

    base_scope = current_business.productos
                                 .includes(:categoria, :profit_margin_preset, :product_variations, stock_lots: [{ stock_lot_variations: :product_variation },
                                                                                                                { purchase_invoice_item: :purchase_invoice }])
                                 .order(Arel.sql('LOWER(productos.descripcion) ASC, productos.id ASC'))

    @has_productos = current_business.productos.exists?
    @filters_applied = @query_text.present? || @low_stock_filter || @below_target_margin_filter || @selected_categoria_id.present?

    filtered_scope = if @query_text.present?
                       base_scope.whose_name_starts_with(@query_text)
                     else
                       base_scope
                     end

    filtered_scope = filtered_scope.where(categoria_id: @selected_categoria_id) if @selected_categoria_id.present?

    filtered_scope = filter_by_low_stock(filtered_scope) if @low_stock_filter
    filtered_scope = filter_by_below_target_margin(filtered_scope) if @below_target_margin_filter

    @matching_productos_count = filtered_scope.except(:includes).count
    @pagy, @productos = pagy_countless(filtered_scope, items: PRODUCTS_PER_PAGE)
    @next_page = @pagy.next

    render json: paginated_productos_payload if request.format.json?
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

    rows = productos
           .includes(:product_variations)
           .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
           .limit(10)

    render json: rows.map { |row|
      {
        id: row.id,
        descripcion: row.descripcion,
        costo_mayor: nil,
        costo_menor: nil,
        unid_x_pack: nil,
        variations: row.product_variations.order(:id).map { |variation|
          { id: variation.id, description: variation.description }
        }
      }
    }
  end

  def new
    @producto = current_business.productos.new
    @producto.product_variations.build(description: 'Unica', safety_stock: 0)
    load_categorias_for_select
    load_profit_margin_presets_for_select
  end

  def create
    @producto = current_business.productos.new(producto_params)
    if @producto.save
      if request.headers['Turbo-Frame'].present?
        # Render turbo_stream that appends the new row into the index tbody and clears the modal frame
        append_stream = view_context.turbo_stream.append('productos_tbody',
                                                         partial: 'productos/product_table_rows',
                                                         locals: { productos: [@producto] })
        below_target_count = calculate_below_target_margin_total_count
        update_badge_stream = view_context.turbo_stream.update(
          'products-below-target-badge',
          view_context.render(partial: 'productos/below_target_badge', locals: { count: below_target_count })
        )
        set_header_notifications
        refresh_header_notifications_stream = view_context.turbo_stream.replace(
          'notifications-tooltip',
          view_context.render(partial: 'shared/header_notifications')
        )
        clear_frame = view_context.turbo_stream.update('modal-productos', '')
        render turbo_stream: [append_stream, update_badge_stream, refresh_header_notifications_stream, clear_frame]
      else
        redirect_to productos_path, notice: 'Producto creado exitosamente.'
      end
    elsif request.headers['Turbo-Frame'].present?
      load_categorias_for_select
      load_profit_margin_presets_for_select
      frame_html = view_context.turbo_frame_tag('modal-productos') do
        view_context.render(partial: 'form', locals: { producto: @producto })
      end
      render html: frame_html.html_safe, status: :unprocessable_entity, layout: false
    # Render the form partial wrapped in the turbo-frame so Turbo can replace the frame content
    else
      load_categorias_for_select
      load_profit_margin_presets_for_select
      render :new
    end
  end

  def show; end

  def export_excel
    productos = current_business.productos
                               .includes(:categoria, :profit_margin_preset, :product_variations, :stock_lots)
                               .order(Arel.sql('LOWER(productos.descripcion) ASC'))

    headers = [
      'Producto ID',
      'Descripcion',
      'Categoria',
      'Disponible',
      'Precio venta USD',
      'Exento',
      '% ganancia',
      'Preset ganancia',
      'Costo unitario lote alto USD',
      'Precio objetivo USD',
      'Debajo objetivo',
      'Existencia total',
      'Variaciones',
      'Creado en',
      'Actualizado en'
    ]

    table_head = headers.map { |header| "<th>#{sanitize_excel_cell(header)}</th>" }.join
    table_body = productos.map do |producto|
      values = [
        producto.id,
        producto.descripcion,
        producto.categoria&.nombre,
        producto.available? ? 'Si' : 'No',
        producto.precio_venta_usd,
        (producto.respond_to?(:exento) && producto.exento?) ? 'Si' : 'No',
        producto.respond_to?(:porcentaje_ganancia) ? producto.porcentaje_ganancia : nil,
        producto.profit_margin_preset&.name,
        producto.highest_active_lot_unit_cost_usd,
        producto.expected_price_usd_from_target_margin,
        producto.below_target_margin_for_highest_active_lot? ? 'Si' : 'No',
        producto.total_quantity,
        producto.product_variations.size,
        producto.created_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S'),
        producto.updated_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y %H:%M:%S')
      ]

      cells = values.map { |value| "<td>#{sanitize_excel_cell(value)}</td>" }.join
      "<tr>#{cells}</tr>"
    end.join

    html = <<~HTML
      <html>
        <head>
          <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        </head>
        <body>
          <table border="1">
            <thead>
              <tr>#{table_head}</tr>
            </thead>
            <tbody>
              #{table_body}
            </tbody>
          </table>
        </body>
      </html>
    HTML

    filename = "productos_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xls"
    send_data html,
              filename: filename,
              type: 'application/vnd.ms-excel; charset=utf-8',
              disposition: 'attachment'
  end

  def edit
    load_categorias_for_select
    load_profit_margin_presets_for_select
    return unless @producto.product_variations.empty?

    @producto.product_variations.build(description: 'Unica', safety_stock: 0)
  end

  def update
    if @producto.update(producto_params)
      if request.headers['Turbo-Frame'].present?
        row_payload = view_context.turbo_stream.append(
          'products-live-updates',
          partial: 'productos/row_update_payload',
          locals: { producto: @producto }
        )
        below_target_count = calculate_below_target_margin_total_count
        update_badge_stream = view_context.turbo_stream.update(
          'products-below-target-badge',
          view_context.render(partial: 'productos/below_target_badge', locals: { count: below_target_count })
        )
        set_header_notifications
        refresh_header_notifications_stream = view_context.turbo_stream.replace(
          'notifications-tooltip',
          view_context.render(partial: 'shared/header_notifications')
        )
        clear_frame = view_context.turbo_stream.update('modal-productos', '')
        render turbo_stream: [row_payload, update_badge_stream, refresh_header_notifications_stream, clear_frame]
      else
        redirect_to productos_path, notice: 'Producto actualizado exitosamente.'
      end
    else
      load_categorias_for_select
      load_profit_margin_presets_for_select
      if request.headers['Turbo-Frame'].present?
        frame_html = view_context.turbo_frame_tag('modal-productos') do
          view_context.render(partial: 'form', locals: { producto: @producto })
        end
        render html: frame_html.html_safe, status: :unprocessable_entity, layout: false
      else
        render :edit, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RangeError
    @producto.errors.add(:base,
                         'Uno de los valores numéricos está fuera de rango. Revisa porcentaje de ganancia y montos.')
    load_categorias_for_select
    load_profit_margin_presets_for_select
    if request.headers['Turbo-Frame'].present?
      frame_html = view_context.turbo_frame_tag('modal-productos') do
        view_context.render(partial: 'form', locals: { producto: @producto })
      end
      render html: frame_html.html_safe, status: :unprocessable_entity, layout: false
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

  def sanitize_excel_cell(value)
    ERB::Util.html_escape(value.to_s.gsub(/[\r\n]/, ' ').strip)
  end

  def set_producto
    @producto = current_business.productos.find(params[:id])
  end

  def producto_params
    allowed = [
      :descripcion,
      :precio_venta_usd,
      :categoria_id,
      :foto,
      :porcentaje_ganancia,
      :profit_margin_preset_id,
      { product_variations_attributes: %i[id description safety_stock _destroy] }
    ]
    allowed << :exento if Producto.column_names.include?('exento')

    params.require(:producto).permit(*allowed)
  end

  def load_categorias_for_select
    @categorias_for_select = current_business.categorias.order(nombre: :asc)
  end

  def load_profit_margin_presets_for_select
    @profit_margin_presets_for_select = current_business.profit_margin_presets.order(percentage: :asc)
  end

  def paginated_productos_payload
    {
      table_rows_html: render_product_table_rows,
      next_page: @next_page,
      batch_count: @productos.size
    }
  end

  def render_product_table_rows
    render_to_string(
      partial: 'productos/product_table_rows',
      formats: [:html],
      locals: { productos: @productos }
    )
  end

  def filter_by_low_stock(scope)
    low_stock_product_ids = ProductVariation
                            .joins(:producto)
                            .where(productos: { business_id: current_business.id })
                            .where('COALESCE(product_variations.safety_stock, 0) > 0')
                            .left_joins(:stock_lot_variations)
                            .group('product_variations.id', 'product_variations.producto_id', 'product_variations.safety_stock')
                            .having('COALESCE(SUM(stock_lot_variations.quantity_remaining), 0) <= COALESCE(product_variations.safety_stock, 0)')
                            .select('DISTINCT product_variations.producto_id')

    scope.where(id: low_stock_product_ids)
  end

  def filter_by_below_target_margin(scope)
    under_target_ids = scope.select(&:below_target_margin_for_highest_active_lot?).map(&:id)
    scope.where(id: under_target_ids)
  end

  def calculate_below_target_margin_total_count
    current_business.productos
                    .includes(:profit_margin_preset, :stock_lots)
                    .count(&:below_target_margin_for_highest_active_lot?)
  end
end
