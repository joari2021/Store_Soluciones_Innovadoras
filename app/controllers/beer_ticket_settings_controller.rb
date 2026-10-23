class BeerTicketSettingsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_beer_ticket_setting

  def show
    load_controlled_products
    @selected_controlled_product = @controlled_setting_products.first
  end

  def update
    unless @beer_ticket_setting.update(update_params)
      render json: { errors: @beer_ticket_setting.errors.full_messages }, status: :unprocessable_entity
      return
    end

    render json: {
      enabled: @beer_ticket_setting.enabled,
      next_serial: @beer_ticket_setting.next_serial,
      formatted_next_serial: @beer_ticket_setting.formatted_next_serial
    }
  end

  def search_products
    query = params[:q].to_s.strip
    selected_ids = @beer_ticket_setting.productos.pluck(:id)

    scope = current_business
            .productos
            .where.not(id: selected_ids)
            .includes(foto_attachment: :blob)
            .order(Arel.sql('LOWER(productos.descripcion) ASC'))

    if query.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(query.downcase)
      scope = scope.where('LOWER(productos.descripcion) LIKE ?', "%#{escaped}%")
    end

    products = scope.limit(12)

    render json: products.map { |producto| search_product_payload(producto) }
  end

  def add_product
    producto = current_business.productos.find(params[:producto_id])
    @beer_ticket_setting.beer_ticket_setting_products.find_or_create_by!(producto: producto)

    render_updated_products_payload
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Producto no encontrado.' }, status: :not_found
  end

  def remove_product
    relation = @beer_ticket_setting.beer_ticket_setting_products.includes(:beer_ticket_batches).find_by(producto_id: params[:producto_id])
    if relation&.beer_ticket_batches&.exists?
      render json: { error: 'Este producto ya tiene tickets asociados activos. No se puede quitar.' }, status: :unprocessable_entity
      return
    end

    relation&.destroy

    render_updated_products_payload
  end

  def create_batch
    setting_product = @beer_ticket_setting.beer_ticket_setting_products.find_by(producto_id: params[:producto_id])
    if setting_product.blank?
      render json: { error: 'Selecciona un producto valido para crear tickets.' }, status: :unprocessable_entity
      return
    end

    start_serial = setting_product.next_serial.to_i
    end_serial = params[:end_serial].to_i

    if end_serial < start_serial
      render json: { error: "El serial final debe ser mayor o igual a #{format('%04d', start_serial)}." }, status: :unprocessable_entity
      return
    end

    batch = nil
    BeerTicketBatch.transaction do
      batch = setting_product.beer_ticket_batches.create!(
        start_serial: start_serial,
        end_serial: end_serial,
        ticket_count: (end_serial - start_serial + 1),
        active: true,
      )

      setting_product.update!(next_serial: end_serial + 1)
    end

    render_updated_products_payload(
      message: "Lote creado: #{batch.formatted_start_serial} - #{batch.formatted_end_serial}.",
      batch: batch,
      selected_producto_id: setting_product.producto_id,
    )
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence.presence || e.message }, status: :unprocessable_entity
  end

  def batch_pdf
    batch = @beer_ticket_setting.beer_ticket_batches.includes(beer_ticket_setting_product: { producto: [foto_attachment: :blob] }).find_by(id: params[:batch_id])
    if batch.blank?
      redirect_to beer_ticket_setting_path, alert: 'No se encontro el lote solicitado.'
      return
    end

    pdf_content = BeerTicketsPdfGenerator.new(batch: batch, view_context: view_context).render
    batch.update_columns(printed_at: Time.current) if batch.printed_at.blank?

    filename = "tickets-#{batch.producto.id}-#{batch.formatted_start_serial}-#{batch.formatted_end_serial}.pdf"
    send_data pdf_content, filename: filename, type: 'application/pdf', disposition: 'inline'
  end

  private

  def set_beer_ticket_setting
    @beer_ticket_setting = current_business.beer_ticket_setting || current_business.create_beer_ticket_setting!
  end

  def update_params
    permitted = params.permit(:enabled, :next_serial)
    normalized = {}

    if permitted.key?(:enabled)
      normalized[:enabled] = ActiveModel::Type::Boolean.new.cast(permitted[:enabled])
    end

    if permitted.key?(:next_serial)
      normalized[:next_serial] = [permitted[:next_serial].to_i, 1].max
    end

    normalized
  end

  def load_controlled_products
    @controlled_setting_products = @beer_ticket_setting
                                 .beer_ticket_setting_products
                                 .includes(:beer_ticket_batches, producto: [foto_attachment: :blob])
                                 .joins(:producto)
                                 .order(Arel.sql('LOWER(productos.descripcion) ASC'))
    @controlled_products = @controlled_setting_products.map(&:producto)
    @preview_product = @controlled_products.find { |product| product.foto.attached? } || @controlled_products.first
  end

  def render_updated_products_payload(message: nil, batch: nil, selected_producto_id: nil)
    load_controlled_products

    render json: {
      message: message,
      batch_id: batch&.id,
      selected_producto_id: selected_producto_id,
      products_html: render_to_string(
        partial: 'beer_ticket_settings/controlled_products_list',
        formats: [:html],
        locals: { controlled_products: @controlled_products, setting_products: @controlled_setting_products }
      ),
      preview_html: render_to_string(
        partial: 'beer_ticket_settings/preview_product',
        formats: [:html],
        locals: { preview_product: @preview_product }
      ),
      batches_html: render_to_string(
        partial: 'beer_ticket_settings/product_batches',
        formats: [:html],
        locals: { setting_products: @controlled_setting_products }
      ),
      create_form_html: render_to_string(
        partial: 'beer_ticket_settings/create_batch_form',
        formats: [:html],
        locals: { setting_products: @controlled_setting_products, selected_producto_id: selected_producto_id }
      ),
      count: @controlled_products.size
    }
  end

  def search_product_payload(producto)
    {
      id: producto.id,
      name: producto.display_name_with_presentation,
      image_url: producto.foto.attached? ? url_for(producto.foto) : nil
    }
  end
end
