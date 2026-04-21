class ProductosController < ApplicationController
  PRODUCTS_PER_PAGE = 36

  before_action :require_business
  before_action -> { require_module_access!(:productos) }, except: :search
  before_action :require_search_access!, only: :search
  before_action :set_producto, only: %i[show edit update destroy]
  before_action :set_pack_unwrap, only: %i[edit_unpack_history update_unpack_history destroy_unpack_history]
  before_action :require_admin, except: %i[index search unpack_packs process_unpack unpack_histories edit_unpack_history
                                           update_unpack_history destroy_unpack_history internal_usages create_internal_usage
                                           destroy_internal_usage]
  before_action :require_unpack_access!, only: %i[unpack_packs process_unpack unpack_histories edit_unpack_history
                                                  update_unpack_history destroy_unpack_history]
  before_action :require_internal_usage_access!, only: %i[internal_usages create_internal_usage destroy_internal_usage]

  def index
    @query_text = params[:query_text].to_s.strip
    @low_stock_filter = ActiveModel::Type::Boolean.new.cast(params[:low_stock])
    @below_target_margin_filter = ActiveModel::Type::Boolean.new.cast(params[:below_target_margin])
    @categorias = current_business.categorias.order(nombre: :asc)
    @selected_categoria = @categorias.find_by(id: params[:category_id]) if params[:category_id].present?
    @selected_categoria_id = @selected_categoria&.id
    @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
    @low_stock_total_count = calculate_low_stock_total_count
    @below_target_margin_total_count = calculate_below_target_margin_total_count
    @inventory_global_totals = calculate_inventory_global_totals

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

      rows = if query.present?
               sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
               query_terms = query.downcase.split(/\s+/).map(&:strip).reject(&:blank?).uniq
               products_scope = source_business.productos

               if query_terms.any?
                 products_scope = products_scope.where(
                   query_terms.map.with_index { |_, idx| "LOWER(productos.descripcion) LIKE :term#{idx}" }.join(' OR '),
                   query_terms.each_with_index.to_h { |term, idx| ["term#{idx}".to_sym, "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"] }
                 )
               else
                 products_scope = products_scope.where('productos.descripcion ILIKE ?', "%#{sanitized_query}%")
               end

               scoped_rows = products_scope
                             .includes(:product_variations, :stock_lots)
                             .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
                             .limit(10)

               if scoped_rows.blank?
                 source_business.productos
                                .includes(:product_variations, :stock_lots)
                                .reorder(Arel.sql('LOWER(productos.descripcion) ASC'))
                                .limit(10)
               else
                 scoped_rows
               end
             else
               source_business.productos
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
          exento: row.respond_to?(:exento?) ? row.exento? : false,
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
        low_stock_count = calculate_low_stock_total_count
        below_target_count = calculate_below_target_margin_total_count
        update_low_stock_badge_stream = view_context.turbo_stream.update(
          'products-low-stock-badge',
          view_context.render(partial: 'productos/low_stock_badge', locals: { count: low_stock_count })
        )
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
        render turbo_stream: [append_stream, update_low_stock_badge_stream, update_badge_stream, refresh_header_notifications_stream, clear_frame]
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
                                .includes(:categoria, :product_variations, :stock_lot_variations, :stock_lots)
                                .order(Arel.sql('LOWER(productos.descripcion) ASC'))

    headers = [
      'Producto ID',
      'Variacion ID',
      'Nombre en ventas',
      'Producto base',
      'Presentacion',
      'Variacion',
      'Categoria',
      'Stock variacion',
      'Stock total producto'
    ]

    table_head = headers.map { |header| "<th>#{sanitize_excel_cell(header)}</th>" }.join
    table_rows = []

    productos.each do |producto|
      variation_totals = inventory_variation_totals_for_export(producto)
      total_stock = variation_totals.values.sum.to_d
      total_stock = producto.stock_lots.to_a.sum { |lot| lot.quantity_remaining.to_d } if total_stock.zero?

      variations = producto.product_variations.sort_by(&:id)
      variations = [nil] if variations.empty?

      variations.each do |variation|
        variation_id = variation&.id
        variation_name = variation&.description.to_s.strip.presence || 'Unica'
        variation_stock = if variation_id.present?
                            variation_totals[variation_id].to_d
                          else
                            total_stock
                          end

        if variation_id.present? && variation_stock.zero? && variation_totals.empty? && variations.size == 1
          variation_stock = total_stock
        end

        sales_name = "#{producto.display_name_with_presentation} #{variation_name}".squish

        values = [
          producto.id,
          variation_id,
          sales_name,
          producto.display_name_with_presentation,
          producto.presentation.to_s,
          variation_name,
          producto.categoria&.nombre,
          variation_stock,
          total_stock
        ]

        table_rows << { sales_name: sales_name, values: values }
      end
    end

    sorted_rows = table_rows.sort_by do |row|
      I18n.transliterate(row[:sales_name].to_s).downcase
    end
    table_body = sorted_rows.map do |row|
      cells = row[:values].map { |value| "<td>#{sanitize_excel_cell(value)}</td>" }.join
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

    filename = "inventario_productos_variaciones_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xls"
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
    propagate_photo_to_same_name_products = image_update_requested?
    if params[:producto].is_a?(ActionController::Parameters) && params[:producto].key?(:allow_unpack)
      update_attrs['allow_unpack'] = extract_allow_unpack_param
    end

    if @producto.update(update_attrs)
      sync_product_image_to_other_businesses!(@producto) if propagate_photo_to_same_name_products

      if request.headers['Turbo-Frame'].present?
        row_payload = view_context.turbo_stream.append(
          'products-live-updates',
          partial: 'productos/row_update_payload',
          locals: { producto: @producto }
        )
        low_stock_count = calculate_low_stock_total_count
        below_target_count = calculate_below_target_margin_total_count
        update_low_stock_badge_stream = view_context.turbo_stream.update(
          'products-low-stock-badge',
          view_context.render(partial: 'productos/low_stock_badge', locals: { count: low_stock_count })
        )
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
        render turbo_stream: [row_payload, update_low_stock_badge_stream, update_badge_stream, refresh_header_notifications_stream, clear_frame]
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
      respond_to do |format|
        format.html { redirect_to productos_path, notice: 'Producto eliminado exitosamente.' }
        format.json do
          render json: {
            success: true,
            product_id: @producto.id,
            low_stock_total_count: calculate_low_stock_total_count,
            below_target_margin_total_count: calculate_below_target_margin_total_count,
          }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to productos_path, alert: 'No se pudo eliminar el producto.' }
        format.json do
          render json: { error: 'No se pudo eliminar el producto.' }, status: :unprocessable_entity
        end
      end
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
      lot_breakdown = producto.consume_variation_stock_with_breakdown!(variation_id: variation.id, quantity_units: quantity)
      usage.stock_lot_breakdown = lot_breakdown.map do |entry|
        {
          'stock_lot_id' => entry[:stock_lot_id].to_i,
          'quantity' => entry[:quantity].to_d.to_s('F')
        }
      end
      usage.save!
    end

    redirect_to internal_usages_productos_path, notice: 'Uso interno registrado y descontado del inventario.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to internal_usages_productos_path,
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def destroy_internal_usage
    usage = current_business.product_usages
                           .includes(:producto, :product_variation)
                           .find(params[:id])

    ActiveRecord::Base.transaction do
      restore_stock_for_internal_usage!(usage, strict: false)
      usage.destroy!
    end

    redirect_to internal_usages_productos_path,
                notice: 'Uso interno eliminado. Si no existe el lote original, la restauracion de stock puede quedar parcial.'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
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
                       .where('stock_lot_variations.quantity_remaining > 0')
                       .joins(:stock_lot)
                       .pluck('stock_lots.unit_cost_usd')
                       .map(&:to_d)

    return 0.to_d if lot_costs.blank?

    lot_costs.max
  end

  def inventory_variation_totals_for_export(producto)
    variation_rows = producto.stock_lot_variations.to_a
    variation_groups = variation_rows.group_by(&:product_variation_id)
    variation_totals = variation_groups.transform_values do |rows|
      rows.sum { |row| row.quantity_remaining.to_d }
    end

    if producto.product_variations.size == 1
      unique_variation_id = producto.product_variations.first.id
      nil_variation_total = variation_totals[nil].to_d

      if nil_variation_total.positive?
        variation_totals[unique_variation_id] = variation_totals[unique_variation_id].to_d + nil_variation_total
        variation_totals.delete(nil)
      end
    end

    variation_totals
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

  def restore_stock_for_internal_usage!(usage, strict: true)
    producto = usage.producto
    variation = usage.product_variation

    if producto.blank? || variation.blank?
      return unless strict

      raise ActiveRecord::RecordInvalid.new(usage),
            'No se pudo restaurar el stock: producto o variacion no disponible en el registro.'
    end

    breakdown_rows = Array(usage.stock_lot_breakdown)
    restored_total = 0.to_d

    breakdown_rows.each do |row|
      source = row.respond_to?(:to_h) ? row.to_h : {}
      stock_lot_id = (source['stock_lot_id'] || source[:stock_lot_id]).to_i
      quantity_units = parse_unpack_decimal(source['quantity'] || source[:quantity])
      next if stock_lot_id <= 0 || !quantity_units.positive?

      stock_lot = producto.stock_lots.find_by(id: stock_lot_id)
      next if stock_lot.blank?

      restore_variation_units_in_lot!(
        stock_lot: stock_lot,
        variation_id: variation.id,
        quantity_units: quantity_units,
        usage: usage,
        strict: strict
      )
      restored_total += quantity_units
    end

    remaining_to_restore = usage.quantity.to_d - restored_total
    return if remaining_to_restore <= 0

    restore_variation_units_fifo!(
      producto: producto,
      variation_id: variation.id,
      quantity_units: remaining_to_restore,
      usage: usage,
      strict: strict
    )
  end

  def restore_variation_units_in_lot!(stock_lot:, variation_id:, quantity_units:, usage:, strict: true)
    row = stock_lot.variation_row_for(variation_id, create_if_missing: true)
    if row.blank?
      return unless strict

      raise ActiveRecord::RecordInvalid.new(usage),
            "No se pudo restaurar en el lote ##{stock_lot.id}: variacion no encontrada."
    end

    current_remaining = row.quantity_remaining.to_d
    max_quantity = row.quantity_in.to_d
    available_capacity = max_quantity - current_remaining

    if quantity_units.to_d > available_capacity
      return unless strict

      raise ActiveRecord::RecordInvalid.new(usage),
            "No se pudo restaurar en el lote ##{stock_lot.id}: capacidad insuficiente para revertir #{quantity_units.to_f.round(4)} unidad(es)."
    end

    row.update!(quantity_remaining: current_remaining + quantity_units.to_d)
    stock_lot.sync_quantity_remaining_from_variations!
  end

  def restore_variation_units_fifo!(producto:, variation_id:, quantity_units:, usage:, strict: true)
    remaining_to_restore = quantity_units.to_d

    producto.stock_lots.ordered_fifo.each do |lot|
      row = lot.variation_row_for(variation_id, create_if_missing: true)
      next unless row

      current_remaining = row.quantity_remaining.to_d
      max_quantity = row.quantity_in.to_d
      available_capacity = max_quantity - current_remaining
      next unless available_capacity.positive?

      restored = [available_capacity, remaining_to_restore].min
      next unless restored.positive?

      row.update!(quantity_remaining: current_remaining + restored)
      lot.sync_quantity_remaining_from_variations!

      remaining_to_restore -= restored
      break if remaining_to_restore <= 0
    end

    return if remaining_to_restore <= 0
    return unless strict

    raise ActiveRecord::RecordInvalid.new(usage),
          "No se pudo restaurar todo el stock del uso interno ##{usage.id} (faltan #{remaining_to_restore.to_f.round(4)} unidades)."
  end

  def usage_form_params
    params.permit(:producto_id, :product_variation_id, :quantity, :used_on, :notes)
  end

  def extract_allow_unpack_param
    raw_value = params.dig(:producto, :allow_unpack)
    raw_value = raw_value.last if raw_value.is_a?(Array)
    ActiveModel::Type::Boolean.new.cast(raw_value)
  end

  def image_update_requested?
    image_param = params.dig(:producto, :foto)
    image_param.respond_to?(:content_type)
  end

  def sync_product_image_to_other_businesses!(source_product)
    return unless source_product.foto.attached?

    Producto
      .where(descripcion: source_product.descripcion)
      .where.not(id: source_product.id)
      .where.not(business_id: source_product.business_id)
      .find_each do |target_product|
      target_product.foto.attach(source_product.foto.blob)
    end
  rescue StandardError => e
    Rails.logger.warn("[PRODUCT_IMAGE_SYNC] No se pudo sincronizar imagen del producto ##{source_product.id}: #{e.class}: #{e.message}")
  end

  def producto_params
    allowed = [
      :descripcion,
      :presentation,
      :cant_presentation,
      :allow_unpack,
      :general_safety_stock,
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
    low_stock_product_ids = low_stock_product_ids_for_scope(scope)
    return scope.none if low_stock_product_ids.empty?

    scope.where(id: low_stock_product_ids)
  end

  def calculate_low_stock_total_count
    low_stock_product_ids_for_scope(current_business.productos).size
  end

  def filter_by_below_target_margin(scope)
    product_ids = below_target_margin_product_ids(scope)
    return scope.none if product_ids.empty?

    scope.where(id: product_ids)
  end

  def calculate_below_target_margin_total_count
    below_target_margin_product_ids(current_business.productos).size
  end

  def calculate_inventory_global_totals
    productos_scope = current_business.productos.includes(:stock_lots, :stock_lot_variations)

    total_inventory_value_usd = productos_scope.sum do |producto|
      producto.stock_lots.sum do |lot|
        lot.unit_cost_usd.to_d * lot.quantity_remaining.to_d
      end
    end

    total_sale_value_usd = productos_scope.sum do |producto|
      producto.total_quantity.to_d * producto.precio_venta_usd.to_d
    end

    {
      inventory_value_usd: total_inventory_value_usd.round(2),
      sale_value_usd: total_sale_value_usd.round(2)
    }
  end

  def below_target_margin_product_ids(scope)
    relation = scope.except(:includes, :preload, :eager_load)
    relation.includes(:profit_margin_preset, :stock_lots)
            .select(&:below_target_margin_for_highest_active_lot?)
            .map(&:id)
  end

  def low_stock_product_ids_for_scope(scope)
    relation = scope.except(:includes, :preload, :eager_load, :order)
    relation.includes(:product_variations, stock_lots: [:stock_lot_variations, :purchase_invoice_item])
            .select { |producto| product_low_stock?(producto) }
            .map(&:id)
  end

  def product_low_stock?(producto)
    variations = producto.product_variations.to_a
    variation_totals = variation_totals_for_low_stock(producto, variations)

    product_total_quantity = producto.total_quantity.to_d
    product_display_safety_stock = if variations.one?
                                     variations.first.safety_stock.to_d
                                   else
                                     producto.general_safety_stock.to_d
                                   end

    product_row_low_stock = product_display_safety_stock.positive? && product_total_quantity < product_display_safety_stock
    variation_row_low_stock = variations.any? do |variation|
      variation_safety_stock = variation.safety_stock.to_d
      next false unless variation_safety_stock.positive?

      variation_totals[variation.id].to_d < variation_safety_stock
    end

    product_row_low_stock || variation_row_low_stock
  end

  def variation_totals_for_low_stock(producto, variations)
    return {} if variations.empty?

    totals = Hash.new(0.to_d)
    variation_lookup_by_id = variations.index_by(&:id)
    variation_lookup_by_description = variations.index_by { |variation| variation.description.to_s.strip.downcase }

    producto.stock_lots.each do |lot|
      item = lot.purchase_invoice_item
      units_per_pack = item&.unid_x_pack.to_d
      lot_variation_rows = lot.stock_lot_variations.to_a

      if lot_variation_rows.any?
        lot_variation_rows.each do |entry|
          linked_variation = if entry.product_variation_id.present?
                               variation_lookup_by_id[entry.product_variation_id]
                             else
                               variation_lookup_by_description[entry.variation_description.to_s.strip.downcase]
                             end
          linked_variation ||= variations.first if linked_variation.blank? && variations.one?
          next unless linked_variation

          quantity_remaining = entry.quantity_remaining.to_d
          next unless quantity_remaining.positive?

          totals[linked_variation.id] += quantity_remaining
        end
        next
      end

      legacy_rows = item&.variation_breakdown.is_a?(Array) ? item.variation_breakdown : []
      if legacy_rows.any?
        legacy_rows.each do |entry|
          legacy_variation_id = (entry['variation_id'] || entry[:variation_id]).presence
          legacy_description = (entry['description'] || entry[:description]).to_s.strip.downcase
          linked_variation = if legacy_variation_id.present?
                               variation_lookup_by_id[legacy_variation_id.to_i]
                             else
                               variation_lookup_by_description[legacy_description]
                             end
          linked_variation ||= variations.first if linked_variation.blank? && variations.one?
          next unless linked_variation

          quantity = (entry['quantity'] || entry[:quantity]).to_d
          next unless quantity.positive?

          totals[linked_variation.id] += quantity
        end
        next
      end

      next unless variations.one?

      lot_quantity_remaining_units = lot.quantity_remaining.to_d * (units_per_pack.positive? ? units_per_pack : 1)
      next unless lot_quantity_remaining_units.positive?

      totals[variations.first.id] += lot_quantity_remaining_units
    end

    totals
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
