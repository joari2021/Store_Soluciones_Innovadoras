module GlobalCatalog
  class SyncGlobalSupplierProductService
    def initialize(global_supplier_product)
      @global_supplier_product = global_supplier_product
    end

    def call
      ensure_mapped_supplier_products!

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

    def ensure_mapped_supplier_products!
      Supplier.where(global_supplier_id: @global_supplier_product.global_supplier_id).find_each do |supplier|
        supplier.business.productos.where(global_product_id: @global_supplier_product.global_product_id).find_each do |producto|
          local_row = SupplierProduct.find_or_initialize_by(supplier_id: supplier.id, producto_id: producto.id)

          if local_row.new_record?
            local_row.global_supplier_product_id = @global_supplier_product.id
            local_row.costo_mayor = @global_supplier_product.costo_mayor
            local_row.cantidad = @global_supplier_product.cantidad
            local_row.costo_menor = @global_supplier_product.costo_menor
            local_row.save!
          elsif local_row.global_supplier_product_id != @global_supplier_product.id
            local_row.update_columns(
              global_supplier_product_id: @global_supplier_product.id,
              updated_at: Time.current,
            )
          end
        end
      end
    end

    def mapped_supplier_products
      SupplierProduct.where(global_supplier_product_id: @global_supplier_product.id)
    end
  end
end
