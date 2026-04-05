class ProductosController < ApplicationController
  PRODUCTS_PER_PAGE = 36

  before_action :require_business
  before_action -> { require_module_access!(:productos) }, except: :search
  before_action :require_search_access!, only: :search
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :set_pack_unwrap, only: %i[edit_unpack_history update_unpack_history destroy_unpack_history]
  before_action :require_admin, except: %i[index search unpack_packs process_unpack unpack_histories edit_unpack_history
                                           update_unpack_history destroy_unpack_history internal_usages create_internal_usage]
  before_action :require_unpack_access!, only: %i[unpack_packs process_unpack unpack_histories edit_unpack_history
                                                  update_unpack_history destroy_unpack_history]
  before_action :require_internal_usage_access!, only: %i[internal_usages create_internal_usage]

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

    @matching_productos_count = filtered_scope.count
    paginated_scope = filtered_scope.includes(:categoria, :profit_margin_preset, :product_variations, stock_lots: [{ stock_lot_variations: :product_variation },
                                                              { purchase_invoice_item: :purchase_invoice }])
    @pagy, @productos = pagy_countless(paginated_scope, items: PRODUCTS_PER_PAGE)
    @next_page = @pagy.next

    render json: paginated_productos_payload if request.format.json?
  end

  def search
    query = params[:q].to_s.strip
    supplier_id = params[:supplier_id].to_s.strip
    source_business_id = params[:source_business_id].to_s.strip

    if source_business_id.present?
      source_business = find_accessible_source_business(source_business_id)
      return render json: [] unless source_business

      productos = if query.present?
                    sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
                    source_business
                      .productos
                      .left_joins(:product_variations)
                      .where(
                        'productos.descripcion ILIKE :q OR CAST(productos.presentation AS TEXT) ILIKE :q OR product_variations.description ILIKE :q',
                        q: "%#{sanitized_query}%"
                      )
                      .distinct
                  else
                    Producto.none
                  end

            rows = productos
              .includes(:product_variations, :stock_lots)
              .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
              .limit(10)

            if rows.blank?
         rows = source_business
           .productos
           .includes(:product_variations, :stock_lots)
           .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
           .limit(10)
            end

      payload = rows.map do |row|
        variations = row.product_variations.order(:id).map do |variation|
          {
            id: variation.id,
            description: variation.description,
            purchase_cost_usd: highest_active_lot_cost_for_variation(row, variation)
          }
        end

        {
          id: row.id,
          descripcion: row.descripcion,
          display_name: row.display_name_with_presentation,
          costo_mayor: row.highest_active_lot_unit_cost_usd.to_d,
          costo_menor: row.highest_active_lot_unit_cost_usd.to_d,
          unid_x_pack: 1,
          exento: true,
          variations: variations
        }
      end

      render json: payload
      return
    end

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
               'productos.*',
               'supplier_products.costo_mayor AS supplier_costo_mayor',
               'supplier_products.costo_menor AS supplier_costo_menor',
               'supplier_products.cantidad AS supplier_unid_x_pack'
             )

      payload = rows.map do |row|
        {
          id: row.id,
          descripcion: row.descripcion,
          display_name: row.display_name_with_presentation,
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
        display_name: row.display_name_with_presentation,
        costo_mayor: nil,
        costo_menor: nil,
        unid_x_pack: nil,
        variations: row.product_variations.order(:id).map { |variation|
          { id: variation.id, description: variation.description }
        }
      }
    }
  rescue StandardError => e
    Rails.logger.error("[PRODUCT_SEARCH_ERROR] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(20).join("\n"))
    render json: [], status: :ok
  end

  def new
    @producto = current_business.productos.new
    @producto.product_variations.build(description: 'Unica', safety_stock: 0)
    load_categorias_for_select
    load_profit_margin_presets_for_select
  end

  def create
    @producto = current_business.productos.new(producto_params)
    if params[:producto].is_a?(ActionController::Parameters) && params[:producto].key?(:allow_unpack)
      @producto.allow_unpack = extract_allow_unpack_param
    end
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
        product_available_for_export?(producto) ? 'Si' : 'No',
        producto.precio_venta_usd,
        producto.respond_to?(:exento) && producto.exento? ? 'Si' : 'No',
        producto.respond_to?(:porcentaje_ganancia) ? producto.porcentaje_ganancia : nil,
        product_profit_margin_preset_for_export(producto),
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
    update_attrs = producto_params.to_h
    if params[:producto].is_a?(ActionController::Parameters) && params[:producto].key?(:allow_unpack)
      update_attrs['allow_unpack'] = extract_allow_unpack_param
    end

    if @producto.update(update_attrs)
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

  def unpack_packs
    @query_text = params[:query_text].to_s.strip
    scope = current_business.productos
                            .includes(:product_variations, :stock_lot_variations, :stock_lots)
                            .where(presentation: Producto.presentations[:pack])
                            .where(allow_unpack: true)
                            .order(Arel.sql('LOWER(productos.descripcion) ASC'))

    if @query_text.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(@query_text)
      scope = scope.where('productos.descripcion ILIKE ?', "%#{escaped}%")
    end

    @pack_products = scope.to_a
    @pack_products_payload = @pack_products.map do |producto|
      {
        id: producto.id,
        name: producto.display_name_with_presentation,
        cant_presentation: producto.cant_presentation.to_i,
        total_stock: producto.total_quantity.to_d.to_f,
        variations: producto.product_variations.sort_by(&:id).map do |variation|
          {
            id: variation.id,
            name: variation.description.to_s,
            available: available_variation_quantity(producto: producto, variation: variation).to_d.to_f
          }
        end
      }
    end
  end

  def process_unpack
    pack_product = current_business.productos.find_by(id: params[:product_id])
    return redirect_to unpack_packs_productos_path, alert: 'Producto pack no encontrado.' if pack_product.blank?
    unless pack_product.pack?
      return redirect_to unpack_packs_productos_path, alert: 'Solo se pueden destapar productos tipo pack.'
    end

    parsed_rows = parse_unpack_rows(params[:rows])
    if parsed_rows.empty?
      return redirect_to unpack_packs_productos_path,
                         alert: 'Debes seleccionar al menos una variacion con packs a destapar.'
    end

    performed_on = parse_filter_date(params[:performed_on]) || Time.current.in_time_zone('America/Caracas').to_date

    ActiveRecord::Base.transaction do
      apply_unpack!(pack_product: pack_product, parsed_rows: parsed_rows, performed_on: performed_on)
    end

    redirect_to unpack_packs_productos_path, notice: 'Desempaque registrado correctamente.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to unpack_packs_productos_path, alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def unpack_histories
    @selected_fecha_desde = parse_filter_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_filter_date(params[:fecha_hasta])
    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    scope = current_business.pack_unwraps
                            .includes(:user, :pack_producto, :unit_producto, pack_unwrap_items: %i[source_product_variation])
                            .order(performed_at: :desc, id: :desc)

    scope = scope.where('performed_on >= ?', @selected_fecha_desde) if @selected_fecha_desde.present?
    scope = scope.where('performed_on <= ?', @selected_fecha_hasta) if @selected_fecha_hasta.present?

    @pack_unwraps = scope
  end

  def internal_usages
    @selected_fecha_desde = parse_filter_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_filter_date(params[:fecha_hasta])
    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    scope = current_business.product_usages
                            .includes(:producto, :product_variation, :user)
                            .order(used_on: :desc, id: :desc)

    scope = scope.where('used_on >= ?', @selected_fecha_desde) if @selected_fecha_desde.present?
    scope = scope.where('used_on <= ?', @selected_fecha_hasta) if @selected_fecha_hasta.present?

    @product_usages = scope

    @usage_products = current_business.productos
                                      .includes(:product_variations, :stock_lot_variations, :stock_lots)
                                      .order(Arel.sql('LOWER(productos.descripcion) ASC'))

    default_date = Time.current.in_time_zone('America/Caracas').to_date
    @usage_form_date = default_date.strftime('%d-%m-%Y')
    @usage_products_payload = @usage_products.map do |producto|
      {
        id: producto.id,
        name: producto.display_name_with_presentation,
        variations: producto.product_variations.sort_by(&:id).map do |variation|
          {
            id: variation.id,
            name: variation.description.to_s,
            available: available_variation_quantity(producto: producto, variation: variation).to_d.to_f
          }
        end
      }
    end
  end

  def create_internal_usage
    producto = current_business.productos.find_by(id: usage_form_params[:producto_id])
    return redirect_to internal_usages_productos_path, alert: 'Producto no encontrado.' if producto.blank?

    variation = producto.product_variations.find_by(id: usage_form_params[:product_variation_id])
    if variation.blank?
      return redirect_to internal_usages_productos_path,
                         alert: 'Debes seleccionar una variacion valida para registrar el uso.'
    end

    quantity = parse_unpack_decimal(usage_form_params[:quantity])
    used_on = parse_filter_date(usage_form_params[:used_on]) || Time.current.in_time_zone('America/Caracas').to_date

    usage = current_business.product_usages.new(
      producto: producto,
      product_variation: variation,
      user: Current.user,
      quantity: quantity,
      used_on: used_on,
      notes: usage_form_params[:notes]
    )

    ActiveRecord::Base.transaction do
      producto.consume_variation_stock!(variation_id: variation.id, quantity_units: quantity)
      usage.save!
    end

    redirect_to internal_usages_productos_path, notice: 'Uso interno registrado y descontado del inventario.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to internal_usages_productos_path,
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def edit_unpack_history
    @pack_producto = @pack_unwrap.pack_producto
    @unit_producto = @pack_unwrap.unit_producto

    @rows = @pack_producto.product_variations.sort_by(&:id).map do |variation|
      current_packs = @pack_unwrap.pack_unwrap_items
                                  .select { |item| item.source_product_variation_id == variation.id }
                                  .sum { |item| item.packs_opened.to_d }

      available_now = available_variation_quantity(producto: @pack_producto, variation: variation)
      max_editable = (available_now + current_packs).to_d

      {
        variation: variation,
        current_packs: current_packs,
        max_editable: max_editable
      }
    end
  end

  def update_unpack_history
    parsed_rows = parse_unpack_rows(params[:rows])
    if parsed_rows.empty?
      return redirect_to edit_unpack_history_productos_path(@pack_unwrap),
                         alert: 'Debes indicar al menos una variacion con packs.'
    end

    performed_on = parse_filter_date(params[:performed_on]) || @pack_unwrap.performed_on

    ActiveRecord::Base.transaction do
      revert_unpack!(@pack_unwrap, destroy_record: false)
      apply_unpack!(
        pack_product: @pack_unwrap.pack_producto,
        parsed_rows: parsed_rows,
        performed_on: performed_on,
        target_unwrap: @pack_unwrap
      )
    end

    redirect_to unpack_histories_productos_path, notice: 'Desempaque actualizado correctamente.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_unpack_history_productos_path(@pack_unwrap),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def destroy_unpack_history
    ActiveRecord::Base.transaction do
      revert_unpack!(@pack_unwrap, destroy_record: true)
    end

    redirect_to unpack_histories_productos_path, notice: 'Desempaque revertido correctamente.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to unpack_histories_productos_path,
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  private

  def require_search_access!
    return if current_user_admin?
    return if can_access_module?(:productos)
    return if can_access_module?(:ventas)

    render json: { error: 'Acceso denegado.' }, status: :forbidden
  end

  def find_accessible_source_business(raw_id)
    business_id = raw_id.to_i
    return nil if business_id <= 0
    return nil if current_business.present? && business_id == current_business.id

    # Intercompany purchase invoices are admin-only; keep source lookup direct
    # to avoid accidental filtering that returns empty catalogs.
    Business.find_by(id: business_id)
  end

  def highest_active_lot_cost_for_variation(producto, variation)
    lot_costs = producto.stock_lot_variations
                       .where(product_variation_id: variation.id)
                       .where('quantity_remaining > 0')
                       .joins(:stock_lot)
                       .pluck('stock_lots.unit_cost_usd')
                       .map(&:to_d)

    return 0.to_d if lot_costs.blank?

    lot_costs.max
  end

  def product_available_for_export?(producto)
    return producto.available? if producto.respond_to?(:available?)
    return producto.disponible? if producto.respond_to?(:disponible?)
    return ActiveModel::Type::Boolean.new.cast(producto[:available]) if producto.has_attribute?(:available)
    return ActiveModel::Type::Boolean.new.cast(producto[:disponible]) if producto.has_attribute?(:disponible)

    true
  end

  def product_profit_margin_preset_for_export(producto)
    preset = producto.profit_margin_preset
    return nil if preset.blank?

    return preset.name if preset.respond_to?(:name) && preset.name.present?
    return "#{preset.percentage}%" if preset.respond_to?(:percentage) && preset.percentage.present?

    preset.to_s
  end

  def sanitize_excel_cell(value)
    ERB::Util.html_escape(value.to_s.gsub(/[\r\n]/, ' ').strip)
  end

  def set_producto
    @producto = current_business.productos.find(params[:id])
  end

  def set_pack_unwrap
    @pack_unwrap = current_business.pack_unwraps
                                   .includes(:pack_producto, :unit_producto, :pack_unwrap_items)
                                   .find(params[:id])
  end

  def require_unpack_access!
    return if current_user_admin? || current_user_manager?

    deny_access('Solo encargado o administrador puede usar destapar pack e historial.')
  end

  def require_internal_usage_access!
    return if current_user_admin? || current_user_manager?

    deny_access('Solo encargado o administrador puede registrar uso interno de productos.')
  end

  def usage_form_params
    params.permit(:producto_id, :product_variation_id, :quantity, :used_on, :notes)
  end

  def extract_allow_unpack_param
    raw_value = params.dig(:producto, :allow_unpack)
    raw_value = raw_value.last if raw_value.is_a?(Array)
    ActiveModel::Type::Boolean.new.cast(raw_value)
  end

  def producto_params
    allowed = [
      :descripcion,
      :presentation,
      :cant_presentation,
      :allow_unpack,
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

  def parse_unpack_rows(raw_rows)
    row_list =
      case raw_rows
      when ActionController::Parameters
        raw_rows.to_unsafe_h.values
      when Hash
        raw_rows.values
      else
        Array(raw_rows)
      end

    row_list.filter_map do |raw_row|
      row = if raw_row.is_a?(ActionController::Parameters)
              raw_row.permit(:variation_id, :packs).to_h
            elsif raw_row.respond_to?(:to_h)
              raw_row.to_h
            else
              {}
            end

      variation_id = row[:variation_id] || row['variation_id']
      packs = parse_unpack_decimal(row[:packs] || row['packs'])

      next if variation_id.blank? || !packs.positive?

      {
        variation_id: variation_id.to_i,
        packs: packs.to_d.round(2)
      }
    end
  end

  def parse_filter_date(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    Date.strptime(value, '%Y-%m-%d')
  rescue ArgumentError
    begin
      Date.strptime(value, '%d-%m-%Y')
    rescue ArgumentError
      nil
    end
  end

  def parse_unpack_decimal(raw_value)
    return raw_value.to_d if raw_value.is_a?(Numeric)

    compact = raw_value.to_s.strip
    return 0.to_d if compact.blank?

    normalized = if compact.include?(',')
                   compact.gsub('.', '').tr(',', '.')
                 elsif compact.count('.') > 1 && compact.split('.').drop(1).all? { |group| group.length == 3 }
                   compact.delete('.')
                 else
                   compact
                 end

    BigDecimal(normalized)
  rescue ArgumentError
    0.to_d
  end

  def normalize_product_base_description(raw_value)
    value = raw_value.to_s.strip.downcase
    return '' if value.blank?

    value = value.gsub(/\s*\(pack\s+de\s+\d+\s+unid\)\s*\z/i, '')
    value = value.gsub(/\s*\(unidad\)\s*\z/i, '')
    value.strip
  end

  def available_variation_quantity(producto:, variation:)
    variation_rows = producto.stock_lot_variations.to_a
    grouped = variation_rows.group_by(&:product_variation_id)
    total = grouped[variation.id].to_a.sum { |row| row.quantity_remaining.to_d }
    return total if total.positive?

    if variation_rows.empty? && producto.product_variations.size == 1
      return producto.stock_lots.to_a.sum { |lot| lot.quantity_remaining.to_d }
    end

    0.to_d
  end

  def apply_unpack!(pack_product:, parsed_rows:, performed_on:, target_unwrap: nil)
    pack_base_description = normalize_product_base_description(pack_product.descripcion)

    unit_scope = current_business.productos.where(presentation: :unidad)
    unit_product = unit_scope.find_by('LOWER(TRIM(descripcion)) = ?', pack_base_description)
    unit_product ||= unit_scope.detect do |producto|
      normalize_product_base_description(producto.descripcion) == pack_base_description
    end

    if unit_product.blank?
      raise ActiveRecord::RecordInvalid.new(pack_product),
            'No existe el producto unidad con el mismo nombre para realizar el desempaque.'
    end

    cant_presentation = pack_product.cant_presentation.to_i
    if cant_presentation <= 0
      raise ActiveRecord::RecordInvalid.new(pack_product), 'La cantidad por presentacion del pack es invalida.'
    end

    unwrap = target_unwrap || current_business.pack_unwraps.build
    unwrap.pack_unwrap_items.destroy_all if target_unwrap.present?

    unwrap.assign_attributes(
      pack_producto: pack_product,
      unit_producto: unit_product,
      user: Current.user,
      cant_presentation: cant_presentation,
      total_packs_opened: 0,
      total_units_created: 0,
      performed_on: performed_on,
      performed_at: Time.current,
      notes: 'Lote por desempaque'
    )
    unwrap.save!

    parsed_rows.each do |row|
      source_variation = pack_product.product_variations.find_by(id: row[:variation_id])
      if source_variation.blank?
        raise ActiveRecord::RecordInvalid.new(pack_product), 'La variacion seleccionada no existe en el producto pack.'
      end

      destination_variation = unit_product.product_variations.find_by('LOWER(description) = ?',
                                                                      source_variation.description.to_s.strip.downcase)
      if destination_variation.blank?
        raise ActiveRecord::RecordInvalid.new(unit_product),
              "No se puede destapar: la variacion '#{source_variation.description}' no existe en el producto unidad destino."
      end

      remaining_packs = row[:packs].to_d
      next unless remaining_packs.positive?

      pack_product.stock_lots.ordered_fifo.each do |source_lot|
        break unless remaining_packs.positive?

        available_in_lot = source_lot.available_variation_units(source_variation.id)
        next unless available_in_lot.positive?

        packs_to_open = [available_in_lot, remaining_packs].min.round(2)
        next unless packs_to_open.positive?

        consumed_packs = source_lot.consume_variation_units!(variation_id: source_variation.id,
                                                             quantity_units: packs_to_open)
        next unless consumed_packs.positive?

        units_created = (consumed_packs * cant_presentation).round(2)
        destination_unit_cost = (source_lot.unit_cost_usd.to_d / cant_presentation.to_d).round(2)

        destination_lot = unit_product.stock_lots.create!(
          factura_item_id: nil,
          unit_cost_usd: destination_unit_cost,
          quantity_in: units_created,
          quantity_remaining: units_created,
          purchased_at: Time.current,
          supplier_name: 'Lote por desempaque',
          description: 'Lote por desempaque'
        )

        destination_lot.stock_lot_variations.create!(
          product_variation_id: destination_variation.id,
          variation_description: destination_variation.description.to_s,
          quantity_in: units_created,
          quantity_remaining: units_created
        )
        destination_lot.sync_quantity_remaining_from_variations!

        unwrap.pack_unwrap_items.create!(
          source_product_variation: source_variation,
          destination_product_variation: destination_variation,
          source_stock_lot: source_lot,
          destination_stock_lot: destination_lot,
          packs_opened: consumed_packs,
          units_created: units_created,
          source_unit_cost_usd: source_lot.unit_cost_usd.to_d,
          destination_unit_cost_usd: destination_unit_cost
        )

        unwrap.total_packs_opened = unwrap.total_packs_opened.to_d + consumed_packs
        unwrap.total_units_created = unwrap.total_units_created.to_d + units_created

        remaining_packs -= consumed_packs
      end

      if remaining_packs.positive?
        raise ActiveRecord::RecordInvalid.new(pack_product),
              "Stock insuficiente para la variacion #{source_variation.description} (faltan #{remaining_packs.to_d.round(2).to_s('F')} packs)."
      end
    end

    unwrap.save!
  end

  def revert_unpack!(unwrap, destroy_record: true)
    destination_lots_to_destroy = []

    unwrap.pack_unwrap_items.includes(:source_stock_lot, :destination_stock_lot).find_each do |item|
      source_lot = item.source_stock_lot
      destination_lot = item.destination_stock_lot

      if destination_lot.present?
        destination_row = destination_lot.stock_lot_variations.find_by(product_variation_id: item.destination_product_variation_id)
        if destination_row.blank? || destination_row.quantity_remaining.to_d < item.units_created.to_d
          raise ActiveRecord::RecordInvalid.new(unwrap),
                'No se puede revertir el desempaque porque parte de las unidades generadas ya fueron consumidas.'
        end
      end

      if source_lot.present?
        source_row = source_lot.variation_row_for(item.source_product_variation_id, create_if_missing: true)
        if source_row.blank?
          raise ActiveRecord::RecordInvalid.new(unwrap),
                'No se pudo restaurar el stock de origen para una de las variaciones.'
        end

        source_row.update!(quantity_remaining: source_row.quantity_remaining.to_d + item.packs_opened.to_d)
        source_lot.sync_quantity_remaining_from_variations!
      end

      destination_lots_to_destroy << destination_lot if destination_lot.present?
    end

    unwrap.pack_unwrap_items.destroy_all
    destination_lots_to_destroy.uniq.each(&:destroy!)

    if destroy_record
      unwrap.destroy!
    else
      unwrap.update!(total_packs_opened: 0, total_units_created: 0)
    end
  end

  def paginated_productos_payload
    {
      results_html: render_index_results,
      table_rows_html: render_product_table_rows,
      next_page: @next_page,
      batch_count: @productos.size
    }
  end

  def render_index_results
    render_to_string(
      partial: 'productos/index_results',
      formats: [:html]
    )
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
    scope.where(id: below_target_margin_scope(scope).select(:id))
  end

  def calculate_below_target_margin_total_count
    base_scope = current_business.productos
    base_scope.where(id: below_target_margin_scope(base_scope).select(:id)).count
  end

  def below_target_margin_scope(scope)
    relation = scope.except(:includes, :preload, :eager_load, :order)

    relation
      .left_joins(:profit_margin_preset, :stock_lots)
      .group('productos.id')
      .having(<<~SQL.squish)
        MAX(CASE WHEN stock_lots.quantity_remaining > 0 THEN stock_lots.unit_cost_usd ELSE NULL END) IS NOT NULL
        AND COALESCE(MAX(profit_margin_presets.percentage), MAX(productos.porcentaje_ganancia)) IS NOT NULL
        AND MAX(productos.precio_venta_usd) < (
          MAX(CASE WHEN stock_lots.quantity_remaining > 0 THEN stock_lots.unit_cost_usd ELSE NULL END)
          * (1 + (COALESCE(MAX(profit_margin_presets.percentage), MAX(productos.porcentaje_ganancia)) / 100.0))
        )
      SQL
  end
end
