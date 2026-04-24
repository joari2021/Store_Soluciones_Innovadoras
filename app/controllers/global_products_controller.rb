class GlobalProductsController < ApplicationController
  GLOBAL_PRODUCTS_PER_PAGE = 36

  before_action :require_business
  before_action :require_admin
  before_action :set_global_product, only: %i[edit update]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    @query_text = params[:query_text].to_s.strip
    @below_target_margin_filter = ActiveModel::Type::Boolean.new.cast(params[:below_target_margin])
    @category_counts = global_category_counts
    @selected_category = params[:category_name].to_s.strip.presence
    @category_options = @category_counts.keys.sort
    @below_target_margin_total_count = calculate_below_target_margin_total_count

    base_scope = GlobalProduct.order(Arel.sql("LOWER(global_products.name) ASC, global_products.id ASC"))
    @has_global_products = base_scope.exists?

    filtered_scope = base_scope
    if @query_text.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(@query_text.downcase)
      filtered_scope = filtered_scope.where("LOWER(global_products.name) LIKE ?", "%#{escaped}%")
    end

    if @selected_category.present?
      if @selected_category == "Sin categoria"
        filtered_scope = filtered_scope.where("COALESCE(NULLIF(TRIM(global_products.metadata->>'category_name'), ''), '') = ''")
      else
        filtered_scope = filtered_scope.where("LOWER(TRIM(global_products.metadata->>'category_name')) = ?", @selected_category.downcase)
      end
    end

    filtered_scope = filter_by_below_target_margin(filtered_scope) if @below_target_margin_filter

    @filters_applied = @query_text.present? || @selected_category.present? || @below_target_margin_filter
    @matching_global_products_count = filtered_scope.count

    paginated_scope = filtered_scope.includes(:productos, :global_supplier_products, image_attachment: :blob)
    @pagy, @global_products = pagy_countless(paginated_scope, items: GLOBAL_PRODUCTS_PER_PAGE)
    @next_page = @pagy.next

    render json: paginated_global_products_payload if request.format.json?
  end

  def search
    query = params[:q].to_s.strip
    return render json: [] if query.blank?

    escaped = ActiveRecord::Base.sanitize_sql_like(query.downcase)

    products = GlobalProduct
      .where("LOWER(global_products.name) LIKE ?", "%#{escaped}%")
      .order(Arel.sql("LOWER(global_products.name) ASC"))
      .limit(10)

    render json: products.map { |product|
      {
        id: product.id,
        name: product.name,
        display_name: product.display_name_with_presentation,
      }
    }
  end

  def new
    @global_product = GlobalProduct.new(presentation: :unidad, cant_presentation: 1)

    return unless request.headers["Turbo-Frame"].present?

    render_modal_form(
      global_product: @global_product,
      submit_label: "Crear producto global",
      modal_mode: true,
      query_text: params[:query_text],
      category_name: params[:category_name],
      below_target_margin: params[:below_target_margin],
    )
  end

  def create
    @global_product = GlobalProduct.new(global_product_params)
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.save
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      GlobalCatalog::SyncGlobalProductService.new(@global_product).call
      GlobalCatalog::SyncGlobalProductTaxonomyService.new(@global_product).call
      if request.headers["Turbo-Frame"].present?
        prepare_index_state(
          query_text: params[:query_text],
          category_name: params[:category_name],
          below_target_margin: params[:below_target_margin],
        )

        refresh_results = view_context.turbo_stream.update(
          "global-products-results",
          view_context.render(partial: "global_products/index_results")
        )
        clear_frame = view_context.turbo_stream.update("modal-global-products", "")
        render turbo_stream: [refresh_results, clear_frame]
      else
        redirect_to global_products_path, notice: "Producto global creado correctamente."
      end
    else
      if request.headers["Turbo-Frame"].present?
        render_modal_form(
          global_product: @global_product,
          submit_label: "Crear producto global",
          modal_mode: true,
          query_text: params[:query_text],
          category_name: params[:category_name],
          below_target_margin: params[:below_target_margin],
          status: :unprocessable_entity,
        )
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
    return unless request.headers["Turbo-Frame"].present?

    render_modal_form(
      global_product: @global_product,
      submit_label: "Guardar y sincronizar",
      modal_mode: true,
      query_text: params[:query_text],
      category_name: params[:category_name],
      below_target_margin: params[:below_target_margin],
    )
  end

  def update
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.update(global_product_params)
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      GlobalCatalog::SyncGlobalProductService.new(@global_product).call
      GlobalCatalog::SyncGlobalProductTaxonomyService.new(@global_product).call

      if request.headers["Turbo-Frame"].present?
        replace_row = view_context.turbo_stream.replace(
          view_context.dom_id(@global_product, :global_row),
          view_context.render(
            partial: "global_products/table_row",
            locals: {
              product: @global_product,
              row_class: "bg-white",
              flash_row: true,
              query_text: params[:query_text],
              selected_category: params[:category_name],
              below_target_margin_filter: ActiveModel::Type::Boolean.new.cast(params[:below_target_margin]),
            },
          ),
        )
        clear_frame = view_context.turbo_stream.update("modal-global-products", "")
        render turbo_stream: [replace_row, clear_frame]
      else
        redirect_to global_products_path, notice: "Producto global actualizado."
      end
    else
      if request.headers["Turbo-Frame"].present?
        render_modal_form(
          global_product: @global_product,
          submit_label: "Guardar y sincronizar",
          modal_mode: true,
          query_text: params[:query_text],
          category_name: params[:category_name],
          below_target_margin: params[:below_target_margin],
          status: :unprocessable_entity,
        )
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  def set_global_product
    @global_product = GlobalProduct.find(params[:id])
  end

  def global_product_params
    params.require(:global_product).permit(:name, :presentation, :cant_presentation, :active)
  end

  def global_product_metadata_params
    params.fetch(:global_product, {}).permit(
      :category_name,
      :fixed_margin_percentage,
      :sale_price_usd,
    )
  end

  def global_category_counts
    GlobalProduct
      .pluck(Arel.sql("COALESCE(NULLIF(TRIM(global_products.metadata->>'category_name'), ''), 'Sin categoria')"))
      .tally
  end

  def paginated_global_products_payload
    {
      results_html: render_index_results,
      table_rows_html: render_table_rows,
      next_page: @next_page,
      batch_count: @global_products.size,
    }
  end

  def render_index_results
    render_to_string(
      partial: "global_products/index_results",
      formats: [:html],
    )
  end

  def render_table_rows
    render_to_string(
      partial: "global_products/table_rows",
      formats: [:html],
      locals: { products: @global_products },
    )
  end

  def load_form_collections
    @category_name_options = GlobalCategory.order(Arel.sql("LOWER(global_categories.name) ASC")).pluck(:name)
    @profit_margin_presets_for_select = GlobalProfitMarginPreset.order(:percentage)
  rescue NameError
    @category_name_options = []
    @profit_margin_presets_for_select = []
  end

  def prepare_index_state(query_text:, category_name:, below_target_margin:)
    @query_text = query_text.to_s.strip
    @selected_category = category_name.to_s.strip.presence
    @below_target_margin_filter = ActiveModel::Type::Boolean.new.cast(below_target_margin)
    @category_counts = global_category_counts
    @category_options = @category_counts.keys.sort
    @below_target_margin_total_count = calculate_below_target_margin_total_count

    base_scope = GlobalProduct.order(Arel.sql("LOWER(global_products.name) ASC, global_products.id ASC"))
    @has_global_products = base_scope.exists?

    filtered_scope = base_scope
    if @query_text.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(@query_text.downcase)
      filtered_scope = filtered_scope.where("LOWER(global_products.name) LIKE ?", "%#{escaped}%")
    end

    if @selected_category.present?
      if @selected_category == "Sin categoria"
        filtered_scope = filtered_scope.where("COALESCE(NULLIF(TRIM(global_products.metadata->>'category_name'), ''), '') = ''")
      else
        filtered_scope = filtered_scope.where("LOWER(TRIM(global_products.metadata->>'category_name')) = ?", @selected_category.downcase)
      end
    end

    filtered_scope = filter_by_below_target_margin(filtered_scope) if @below_target_margin_filter

    @filters_applied = @query_text.present? || @selected_category.present? || @below_target_margin_filter
    @matching_global_products_count = filtered_scope.count
    @pagy, @global_products = pagy_countless(
      filtered_scope.includes(:productos, :global_supplier_products, image_attachment: :blob),
      items: GLOBAL_PRODUCTS_PER_PAGE,
    )
    @next_page = @pagy.next
  end

  def render_modal_form(global_product:, submit_label:, modal_mode:, query_text:, category_name:, below_target_margin:, status: :ok)
    global_suppliers_for_product = global_suppliers_for_product(global_product)
    pack_related_global_product = related_pack_global_product_for(global_product)
    pack_related_suppliers_for_product = global_suppliers_for_product(pack_related_global_product)
    pack_supplier_unit_rows = pack_supplier_rows_as_unit_cost(
      pack_product: pack_related_global_product,
      pack_supplier_rows: pack_related_suppliers_for_product,
    )
    cheapest_supplier_cost_unit = cheapest_supplier_cost_unit(global_suppliers_for_product, pack_supplier_unit_rows)

    frame_html = view_context.turbo_frame_tag("modal-global-products") do
      view_context.render(
        partial: "form",
        locals: {
          global_product: global_product,
          submit_label: submit_label,
          modal_mode: modal_mode,
          query_text: query_text,
          category_name: category_name,
          below_target_margin: below_target_margin,
          global_suppliers_for_product: global_suppliers_for_product,
          pack_related_global_product: pack_related_global_product,
          pack_related_suppliers_for_product: pack_related_suppliers_for_product,
          pack_supplier_unit_rows: pack_supplier_unit_rows,
          cheapest_supplier_cost_unit: cheapest_supplier_cost_unit,
        },
      )
    end

    render html: frame_html.html_safe, status: status, layout: false
  end

  def global_suppliers_for_product(global_product)
    return [] unless global_product&.persisted?

    global_product
      .global_supplier_products
      .joins(:global_supplier)
      .includes(:global_supplier)
      .where(active: true)
      .order(Arel.sql("LOWER(global_suppliers.name) ASC"))
  end

  def cheapest_supplier_cost_unit(global_supplier_rows, pack_supplier_unit_rows = [])
    direct_unit_costs = Array(global_supplier_rows)
      .filter_map { |row| row.costo_menor.to_d if row.costo_menor.present? }
      .select(&:positive?)

    pack_unit_costs = Array(pack_supplier_unit_rows)
      .filter_map { |row| row[:unit_cost].to_d if row[:unit_cost].present? }
      .select(&:positive?)

    (direct_unit_costs + pack_unit_costs).min
  end

  def related_pack_global_product_for(global_product)
    return nil unless global_product&.persisted?

    normalized_name = global_product.name.to_s.strip
    return nil if normalized_name.blank?

    GlobalProduct
      .where("LOWER(TRIM(global_products.name)) = ?", normalized_name.downcase)
      .where(presentation: GlobalProduct.presentations[:pack])
      .where.not(id: global_product.id)
      .order(:id)
      .first
  end

  def pack_supplier_rows_as_unit_cost(pack_product:, pack_supplier_rows:)
    units_per_pack = pack_product&.cant_presentation.to_d
    return [] unless units_per_pack.positive?

    Array(pack_supplier_rows).filter_map do |row|
      base_cost = row.costo_menor.to_d
      next unless base_cost.positive?

      {
        supplier_row: row,
        unit_cost: (base_cost / units_per_pack),
      }
    end
  end

  def filter_by_below_target_margin(scope)
    scope.where(below_target_margin_condition_sql)
  end

  def calculate_below_target_margin_total_count
    GlobalProduct.where(below_target_margin_condition_sql).count
  end

  def below_target_margin_condition_sql
    cheapest_cost_sql = <<~SQL.squish
      (
        SELECT MIN(gsp.costo_menor)
        FROM global_supplier_products gsp
        WHERE gsp.global_product_id = global_products.id
          AND gsp.active = TRUE
          AND gsp.costo_menor IS NOT NULL
      )
    SQL

    sale_price_sql = "COALESCE(NULLIF(TRIM(global_products.metadata->>'sale_price_usd'), ''), '0')::numeric"
    fixed_margin_sql = "COALESCE(NULLIF(TRIM(global_products.metadata->>'fixed_margin_percentage'), ''), '0')::numeric"
    objective_price_sql = "(#{cheapest_cost_sql} * (1 + (#{fixed_margin_sql} / 100.0)))"

    "#{cheapest_cost_sql} > 0 AND #{sale_price_sql} < #{objective_price_sql}"
  end
end
