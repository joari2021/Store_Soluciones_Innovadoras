class BeerTicketSettingsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_beer_ticket_setting

  def show
    load_controlled_products
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
    relation = @beer_ticket_setting.beer_ticket_setting_products.find_by(producto_id: params[:producto_id])
    relation&.destroy

    render_updated_products_payload
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
    @controlled_products = @beer_ticket_setting
                           .productos
                           .includes(foto_attachment: :blob)
                           .order(Arel.sql('LOWER(productos.descripcion) ASC'))
    @preview_product = @controlled_products.find { |product| product.foto.attached? } || @controlled_products.first
  end

  def render_updated_products_payload
    load_controlled_products

    render json: {
      products_html: render_to_string(
        partial: 'beer_ticket_settings/controlled_products_list',
        formats: [:html],
        locals: { controlled_products: @controlled_products }
      ),
      preview_html: render_to_string(
        partial: 'beer_ticket_settings/preview_product',
        formats: [:html],
        locals: { preview_product: @preview_product }
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
