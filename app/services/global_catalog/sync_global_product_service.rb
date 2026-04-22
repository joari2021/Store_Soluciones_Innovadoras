module GlobalCatalog
  class SyncGlobalProductService
    def initialize(global_product)
      @global_product = global_product
    end

    def call
      mapped_products.find_each do |local_product|
        updates = {
          descripcion: @global_product.name,
          presentation: @global_product.presentation_before_type_cast,
          cant_presentation: @global_product.cant_presentation,
          exento: @global_product.exento,
          porcentaje_ganancia: @global_product.real_margin_percentage,
          precio_venta_usd: @global_product.sale_price_usd,
          updated_at: Time.current,
        }

        if (category_name = @global_product.category_name).present?
          category = local_product.business.categorias.find_or_create_by!(nombre: category_name)
          updates[:categoria_id] = category.id
        end

        if (fixed_margin = @global_product.fixed_margin_percentage).present?
          preset = local_product.business.profit_margin_presets.find_or_create_by!(percentage: fixed_margin)
          updates[:profit_margin_preset_id] = preset.id
        end

        local_product.update_columns(updates)

        if @global_product.image.attached?
          local_product.foto.attach(@global_product.image.blob)
        end
      end
    end

    private

    def mapped_products
      Producto.where(global_product_id: @global_product.id)
    end
  end
end
