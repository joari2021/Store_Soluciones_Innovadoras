module GlobalCatalog
  class SyncGlobalProductTaxonomyService
    def initialize(global_product)
      @global_product = global_product
    end

    def call
      mapped_products.find_each do |local_product|
        updates = { updated_at: Time.current }

        if (category_name = @global_product.category_name).present?
          category = local_product.business.categorias.find_or_create_by!(nombre: category_name)
          updates[:categoria_id] = category.id
        end

        fixed_margin = @global_product.fixed_margin_percentage
        if fixed_margin.present?
          preset = local_product.business.profit_margin_presets.find_or_create_by!(percentage: fixed_margin)
          updates[:profit_margin_preset_id] = preset.id
          updates[:porcentaje_ganancia] = fixed_margin
        else
          updates[:profit_margin_preset_id] = nil
          updates[:porcentaje_ganancia] = nil
        end

        local_product.update_columns(updates)
      end
    end

    private

    def mapped_products
      Producto.where(global_product_id: @global_product.id)
    end
  end
end