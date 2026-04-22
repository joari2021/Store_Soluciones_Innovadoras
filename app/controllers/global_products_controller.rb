class GlobalProductsController < ApplicationController
  GLOBAL_PRODUCTS_PER_PAGE = 36

  before_action :require_business
  before_action :require_admin
  before_action :set_global_product, only: %i[edit update]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    @query_text = params[:query_text].to_s.strip
    @category_counts = global_category_counts
    @selected_category = params[:category_name].to_s.strip.presence
    @category_options = @category_counts.keys.sort

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

    @filters_applied = @query_text.present? || @selected_category.present?
    @matching_global_products_count = filtered_scope.count

    paginated_scope = filtered_scope.includes(:productos, :global_supplier_products)
    @pagy, @global_products = pagy_countless(paginated_scope, items: GLOBAL_PRODUCTS_PER_PAGE)
    @next_page = @pagy.next

    render json: paginated_global_products_payload if request.format.json?
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
    )
  end

  def create
    @global_product = GlobalProduct.new(global_product_params)
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.save
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      if request.headers["Turbo-Frame"].present?
        prepare_index_state(
          query_text: params[:query_text],
          category_name: params[:category_name],
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
    )
  end

  def update
    @global_product.assign_metadata_attributes!(global_product_metadata_params)

    if @global_product.update(global_product_params)
      @global_product.image.attach(params.dig(:global_product, :image)) if params.dig(:global_product, :image).present?
      GlobalCatalog::SyncGlobalProductService.new(@global_product).call

      if request.headers["Turbo-Frame"].present?
        prepare_index_state(
          query_text: params[:query_text],
          category_name: params[:category_name],
        )

        refresh_results = view_context.turbo_stream.update(
          "global-products-results",
          view_context.render(partial: "global_products/index_results")
        )
        clear_frame = view_context.turbo_stream.update("modal-global-products", "")
        render turbo_stream: [refresh_results, clear_frame]
      else
        redirect_to global_products_path, notice: "Producto global actualizado y sincronizado."
      end
    else
      if request.headers["Turbo-Frame"].present?
        render_modal_form(
          global_product: @global_product,
          submit_label: "Guardar y sincronizar",
          modal_mode: true,
          query_text: params[:query_text],
          category_name: params[:category_name],
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

  def prepare_index_state(query_text:, category_name:)
    @query_text = query_text.to_s.strip
    @selected_category = category_name.to_s.strip.presence
    @category_counts = global_category_counts
    @category_options = @category_counts.keys.sort

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

    @filters_applied = @query_text.present? || @selected_category.present?
    @matching_global_products_count = filtered_scope.count
    @pagy, @global_products = pagy_countless(
      filtered_scope.includes(:productos, :global_supplier_products),
      items: GLOBAL_PRODUCTS_PER_PAGE,
    )
    @next_page = @pagy.next
  end

  def render_modal_form(global_product:, submit_label:, modal_mode:, query_text:, category_name:, status: :ok)
    frame_html = view_context.turbo_frame_tag("modal-global-products") do
      view_context.render(
        partial: "form",
        locals: {
          global_product: global_product,
          submit_label: submit_label,
          modal_mode: modal_mode,
          query_text: query_text,
          category_name: category_name,
        },
      )
    end

    render html: frame_html.html_safe, status: status, layout: false
  end
end
