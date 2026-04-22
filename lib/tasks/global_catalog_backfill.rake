namespace :global_catalog do
  desc "Backfill de catalogo global desde un negocio origen (default BUSINESS_ID=1)"
  task backfill_from_business: :environment do
    business_id = ENV.fetch("BUSINESS_ID", "1").to_i
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

    source_business = Business.find_by(id: business_id)
    raise ArgumentError, "No existe Business con id=#{business_id}" if source_business.blank?

    puts "[GLOBAL CATALOG] Iniciando backfill BUSINESS_ID=#{business_id} DRY_RUN=#{dry_run}"

    counters = {
      global_products_created: 0,
      global_products_updated: 0,
      local_products_mapped: 0,
      global_suppliers_created: 0,
      global_suppliers_updated: 0,
      local_suppliers_mapped: 0,
      global_supplier_products_created: 0,
      global_supplier_products_updated: 0,
      local_supplier_products_mapped: 0,
      skipped_supplier_products: 0,
    }

    product_map = {}
    supplier_map = {}

    runner = lambda do
      source_business.productos.find_each do |producto|
        global_product = GlobalProduct.find_or_initialize_by(
          source_business_id: business_id,
          source_producto_id: producto.id,
        )

        was_new = global_product.new_record?
        global_product.assign_attributes(
          name: producto.descripcion,
          presentation: producto.presentation_before_type_cast,
          cant_presentation: producto.cant_presentation,
          exento: producto.respond_to?(:exento) ? producto.exento : false,
          active: true,
        )
        global_product.save!

        if was_new
          counters[:global_products_created] += 1
        elsif global_product.saved_changes.except("updated_at").any?
          counters[:global_products_updated] += 1
        end

        if producto.global_product_id != global_product.id
          producto.update_columns(global_product_id: global_product.id, updated_at: Time.current)
          counters[:local_products_mapped] += 1
        end

        product_map[producto.id] = global_product.id
      end

      source_business.suppliers.find_each do |supplier|
        global_supplier = GlobalSupplier.find_or_initialize_by(
          source_business_id: business_id,
          source_supplier_id: supplier.id,
        )

        was_new = global_supplier.new_record?
        global_supplier.assign_attributes(
          name: supplier.nombre,
          rif: supplier.rif,
          phone: supplier.telefono,
          mobile_payment_phone: supplier.telefono_pago_movil,
          email: supplier.email,
          address: supplier.direccion,
          bank_account_number: supplier.nro_cuenta,
          pricing_currency_priority: supplier.pricing_currency_priority,
          default_exento: supplier.default_exento,
          active: true,
        )
        global_supplier.save!

        if was_new
          counters[:global_suppliers_created] += 1
        elsif global_supplier.saved_changes.except("updated_at").any?
          counters[:global_suppliers_updated] += 1
        end

        if supplier.global_supplier_id != global_supplier.id
          supplier.update_columns(global_supplier_id: global_supplier.id, updated_at: Time.current)
          counters[:local_suppliers_mapped] += 1
        end

        supplier_map[supplier.id] = global_supplier.id
      end

      SupplierProduct
        .joins(:supplier, :producto)
        .where(suppliers: { business_id: business_id }, productos: { business_id: business_id })
        .find_each do |supplier_product|
        global_product_id = product_map[supplier_product.producto_id]
        global_supplier_id = supplier_map[supplier_product.supplier_id]

        if global_product_id.blank? || global_supplier_id.blank?
          counters[:skipped_supplier_products] += 1
          next
        end

        global_pair = GlobalSupplierProduct.find_or_initialize_by(
          global_supplier_id: global_supplier_id,
          global_product_id: global_product_id,
        )

        was_new = global_pair.new_record?
        global_pair.assign_attributes(
          costo_mayor: supplier_product.costo_mayor,
          cantidad: supplier_product.cantidad,
          costo_menor: supplier_product.costo_menor,
          active: true,
        )
        global_pair.save!

        if was_new
          counters[:global_supplier_products_created] += 1
        elsif global_pair.saved_changes.except("updated_at").any?
          counters[:global_supplier_products_updated] += 1
        end

        if supplier_product.global_supplier_product_id != global_pair.id
          supplier_product.update_columns(global_supplier_product_id: global_pair.id, updated_at: Time.current)
          counters[:local_supplier_products_mapped] += 1
        end
      end
    end

    if dry_run
      ActiveRecord::Base.transaction do
        runner.call
        raise ActiveRecord::Rollback
      end
    else
      ActiveRecord::Base.transaction { runner.call }
    end

    puts "[GLOBAL CATALOG] Backfill completado"
    counters.each do |key, value|
      puts "  - #{key}: #{value}"
    end
    puts(dry_run ? "DRY_RUN: no se persistieron cambios." : "Cambios persistidos correctamente.")
  end
end
