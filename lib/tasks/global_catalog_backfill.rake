namespace :global_catalog do
  desc "Backfill de catalogo global desde un negocio origen (default BUSINESS_ID=1)"
  task backfill_from_business: :environment do
    business_id = ENV.fetch("BUSINESS_ID", "1").to_i
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

    source_business = Business.find_by(id: business_id)
    raise ArgumentError, "No existe Business con id=#{business_id}" if source_business.blank?

    puts "[GLOBAL CATALOG] Iniciando backfill BUSINESS_ID=#{business_id} DRY_RUN=#{dry_run}"

    counters = {
      global_categories_created: 0,
      global_profit_margin_presets_created: 0,
      global_products_created: 0,
      global_products_updated: 0,
      global_product_images_copied: 0,
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
    category_name_map = {}
    margin_percentage_map = {}

    runner = lambda do
      source_business.categorias.find_each do |categoria|
        category_name = categoria.nombre.to_s.strip
        next if category_name.blank?

        global_category = GlobalCategory.find_or_create_by!(name: category_name)
        counters[:global_categories_created] += 1 if global_category.previous_changes.key?("id")
        category_name_map[categoria.id] = global_category.name
      end

      source_business.profit_margin_presets.find_each do |preset|
        percentage = preset.percentage.to_d.round(2)
        global_preset = GlobalProfitMarginPreset.find_or_create_by!(percentage: percentage)
        counters[:global_profit_margin_presets_created] += 1 if global_preset.previous_changes.key?("id")
        margin_percentage_map[preset.id] = global_preset.percentage.to_d
      end

      source_business.productos.find_each do |producto|
        global_product = GlobalProduct.find_or_initialize_by(
          source_business_id: business_id,
          source_producto_id: producto.id,
        )

        category_name = if producto.categoria_id.present?
                          category_name_map[producto.categoria_id].presence || producto.categoria&.nombre.to_s.strip
                        end
        fixed_margin_percentage = if producto.profit_margin_preset_id.present?
                                    margin_percentage_map[producto.profit_margin_preset_id]
                                  elsif producto.respond_to?(:porcentaje_ganancia)
                                    producto.porcentaje_ganancia.to_d
                                  end

        was_new = global_product.new_record?
        global_product.assign_attributes(
          name: producto.descripcion,
          presentation: producto.presentation_before_type_cast,
          cant_presentation: producto.cant_presentation,
          exento: producto.respond_to?(:exento) ? producto.exento : false,
          active: true,
        )
        global_product.assign_metadata_attributes!(
          category_name: category_name,
          fixed_margin_percentage: fixed_margin_percentage,
          sale_price_usd: producto.precio_venta_usd,
        )
        global_product.save!

        if producto.respond_to?(:foto) && producto.foto.attached?
          should_attach_image = global_product.image.blank?

          if global_product.image.attached? && global_product.image.blob.present? && producto.foto.blob.present?
            should_attach_image = global_product.image.blob.checksum != producto.foto.blob.checksum
          end

          if should_attach_image
            global_product.image.attach(producto.foto.blob)
            counters[:global_product_images_copied] += 1
          end
        end

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
