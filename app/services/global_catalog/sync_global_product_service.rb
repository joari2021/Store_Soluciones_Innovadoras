module GlobalCatalog
  class SyncGlobalProductService
    def initialize(global_product)
      @global_product = global_product
    end

    def call
      mapped_products.find_each do |local_product|
        local_product.update_columns(
          descripcion: @global_product.name,
          presentation: @global_product.presentation_before_type_cast,
          cant_presentation: @global_product.cant_presentation,
          exento: @global_product.exento,
          updated_at: Time.current,
        )
      end
    end

    private

    def mapped_products
      Producto.where(global_product_id: @global_product.id)
    end
  end
end
