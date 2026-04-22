module GlobalCatalog
  class SyncGlobalSupplierProductService
    def initialize(global_supplier_product)
      @global_supplier_product = global_supplier_product
    end

    def call
      mapped_supplier_products.find_each do |local_row|
        local_row.update_columns(
          costo_mayor: @global_supplier_product.costo_mayor,
          cantidad: @global_supplier_product.cantidad,
          costo_menor: @global_supplier_product.costo_menor,
          updated_at: Time.current,
        )
      end
    end

    private

    def mapped_supplier_products
      SupplierProduct.where(global_supplier_product_id: @global_supplier_product.id)
    end
  end
end
