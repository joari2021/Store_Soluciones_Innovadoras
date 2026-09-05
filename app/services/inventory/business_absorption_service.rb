module Inventory
  class BusinessAbsorptionService
    Result = Struct.new(:success?, :summary, :errors, :preview)

    def initialize(destination_business:, source_business:, mode:, dry_run: false)
      @destination_business = destination_business
      @source_business = source_business
      @mode = normalize_mode(mode)
      @dry_run = dry_run == true
      @destination_products_cache = {}
      @summary = {
        products_touched: 0,
        destination_products_created: 0,
        lots_transferred: 0,
        units_transferred: 0.to_d,
        lots_skipped_existing: 0,
        absorbed_inventory_value_usd: 0.to_d,
        absorbed_sale_value_usd: 0.to_d,
      }
      @preview_map = {}
    end

    def call
      return Result.new(false, nil, ['Negocio origen no valido.'], nil) if @source_business.blank?
      return Result.new(false, nil, ['Negocio destino no valido.'], nil) if @destination_business.blank?
      return Result.new(false, nil, ['El negocio origen y destino deben ser distintos.'], nil) if @source_business.id == @destination_business.id

      ActiveRecord::Base.transaction do
        source_products.find_each do |source_product|
          process_source_product(source_product)
        end

        raise ActiveRecord::Rollback if @dry_run
      end

      Result.new(true, @summary, [], build_preview_payload)
    rescue ActiveRecord::RecordInvalid => e
      message = if e.record&.errors&.any?
                  e.record.errors.full_messages.to_sentence
                else
                  e.message
                end
      Result.new(false, nil, [message], nil)
    rescue StandardError => e
      Result.new(false, nil, [e.message], nil)
    end

    private

    def source_products
      @source_business.productos.includes(:categoria, :profit_margin_preset, :product_variations, stock_lots: :stock_lot_variations)
    end

    def process_source_product(source_product)
      destination_product = resolve_destination_product!(source_product)
      return if destination_product.blank?

      ensure_preview_product_entry!(destination_product)

      touched = false

      source_product.stock_lots.each do |source_lot|
        source_lot.lock!
        quantity_to_transfer = source_lot_transfer_units(source_lot)
        next unless quantity_to_transfer.positive?

        if absorbed_lot_exists?(source_lot: source_lot, destination_product: destination_product)
          @summary[:lots_skipped_existing] += 1
          next
        end

        create_destination_lot_from_source!(
          source_lot: source_lot,
          source_product: source_product,
          destination_product: destination_product,
          quantity_to_transfer: quantity_to_transfer,
        )

        add_preview_incoming_lot!(
          destination_product: destination_product,
          source_lot: source_lot,
          source_product: source_product,
          quantity_to_transfer: quantity_to_transfer,
        )

        touched = true
        @summary[:lots_transferred] += 1
        @summary[:units_transferred] = @summary[:units_transferred].to_d + quantity_to_transfer
        @summary[:absorbed_inventory_value_usd] = @summary[:absorbed_inventory_value_usd].to_d + (source_lot.unit_cost_usd.to_d * quantity_to_transfer)
        @summary[:absorbed_sale_value_usd] = @summary[:absorbed_sale_value_usd].to_d + (source_product.precio_venta_usd.to_d * quantity_to_transfer)

        next unless @mode == 'move'

        source_lot.quantity_remaining = 0
        source_lot.save!

        source_lot.stock_lot_variations.each do |variation_row|
          variation_row.quantity_remaining = 0
          variation_row.save!
        end
      end

      @summary[:products_touched] += 1 if touched
    end

    def ensure_preview_product_entry!(destination_product)
      key = preview_key_for(destination_product)
      return if @preview_map.key?(key)

      current_quantity = destination_product.total_quantity.to_d
      current_lots = destination_product.stock_lots.order(:id).map do |lot|
        lot_quantity = lot_quantity_units(lot)
        {
          lot_id: lot.id,
          quantity_remaining: lot_quantity,
          unit_cost_usd: lot.unit_cost_usd.to_d,
          total_value_usd: (lot.unit_cost_usd.to_d * lot_quantity).round(4),
          supplier_name: lot.supplier_name.presence || lot.supplier_display_name,
          purchased_at: lot.purchased_at,
        }
      end

      current_inventory_value = current_lots.sum { |lot| lot[:total_value_usd].to_d }
      sale_price_usd = destination_product.precio_venta_usd.to_d

      @preview_map[key] = {
        product_key: key,
        producto_id: destination_product.id,
        descripcion: destination_product.descripcion,
        categoria_nombre: destination_product.categoria&.nombre,
        presentation: destination_product.presentation,
        cant_presentation: destination_product.cant_presentation,
        sale_price_usd: sale_price_usd,
        current_quantity: current_quantity,
        incoming_quantity: 0.to_d,
        projected_quantity: current_quantity,
        current_inventory_value_usd: current_inventory_value,
        incoming_inventory_value_usd: 0.to_d,
        projected_inventory_value_usd: current_inventory_value,
        projected_sale_value_usd: (current_quantity * sale_price_usd).round(4),
        current_lots: current_lots,
        incoming_lots: [],
      }
    end

    def add_preview_incoming_lot!(destination_product:, source_lot:, source_product:, quantity_to_transfer:)
      key = preview_key_for(destination_product)
      preview = @preview_map[key]
      return if preview.blank?

      source_sale_price_usd = source_product.precio_venta_usd.to_d
      incoming_sale_value = (source_sale_price_usd * quantity_to_transfer.to_d).round(4)

      source_variations = source_lot.stock_lot_variations.filter_map do |row|
        quantity = row.quantity_remaining.to_d
        next unless quantity.positive?

        {
          variation_description: row.variation_description,
          quantity_remaining: quantity,
        }
      end

      preview[:incoming_lots] << {
        source_lot_id: source_lot.id,
        quantity_remaining: quantity_to_transfer.to_d,
        unit_cost_usd: source_lot.unit_cost_usd.to_d,
        total_value_usd: (source_lot.unit_cost_usd.to_d * quantity_to_transfer.to_d).round(4),
        source_sale_price_usd: source_sale_price_usd,
        incoming_sale_value_usd: incoming_sale_value,
        supplier_name: source_lot.supplier_name.presence || source_lot.supplier_display_name,
        purchased_at: source_lot.purchased_at,
        variations: source_variations,
      }

      preview[:incoming_quantity] = preview[:incoming_quantity].to_d + quantity_to_transfer.to_d
      preview[:projected_quantity] = preview[:current_quantity].to_d + preview[:incoming_quantity].to_d
      preview[:incoming_inventory_value_usd] = preview[:incoming_inventory_value_usd].to_d + (source_lot.unit_cost_usd.to_d * quantity_to_transfer.to_d)
      preview[:incoming_sale_value_usd] = preview.fetch(:incoming_sale_value_usd, 0.to_d).to_d + incoming_sale_value
      preview[:projected_inventory_value_usd] = preview[:current_inventory_value_usd].to_d + preview[:incoming_inventory_value_usd].to_d
      preview[:projected_sale_value_usd] = (preview[:projected_quantity].to_d * preview[:sale_price_usd].to_d).round(4)
    end

    def build_preview_payload
      {
        generated_at: Time.current,
        products: @preview_map.values.sort_by do |row|
          [row[:descripcion].to_s.downcase, row[:producto_id].to_i]
        end,
      }
    end

    def preview_key_for(destination_product)
      if destination_product.id.present?
        "product-#{destination_product.id}"
      else
        "new-product-#{destination_product.object_id}"
      end
    end

    def resolve_destination_product!(source_product)
      cached = @destination_products_cache[source_product.id]
      return cached if cached.present?

      destination_product = @destination_business.productos.find_by(
        source_business_id: @source_business.id,
        source_product_id: source_product.id,
      )

      if destination_product.blank?
        destination_product = find_destination_product_by_definition(source_product)
      end

      if destination_product.present?
        if destination_product.source_business_id.blank? || destination_product.source_product_id.blank?
          destination_product.update!(
            source_business_id: @source_business.id,
            source_product_id: source_product.id,
          )
        end

        sync_destination_variations!(destination_product: destination_product, source_product: source_product)
        @destination_products_cache[source_product.id] = destination_product
        return destination_product
      end

      destination_category = @destination_business.categorias.find_or_create_by!(
        nombre: source_product.categoria&.nombre.presence || 'General',
      )

      destination_preset = nil
      if source_product.profit_margin_preset.present?
        destination_preset = @destination_business.profit_margin_presets.find_or_create_by!(
          percentage: source_product.profit_margin_preset.percentage,
        )
      end

      destination_product = @destination_business.productos.create!(
        descripcion: source_product.descripcion,
        presentation: source_product.presentation,
        cant_presentation: source_product.cant_presentation,
        allow_unpack: source_product.allow_unpack,
        precio_venta_usd: source_product.precio_venta_usd,
        porcentaje_ganancia: source_product.porcentaje_ganancia,
        categoria: destination_category,
        profit_margin_preset: destination_preset,
        exento: source_product.respond_to?(:exento) ? source_product.exento : false,
        source_business_id: @source_business.id,
        source_product_id: source_product.id,
      )

      source_product.product_variations.order(:id).find_each do |source_variation|
        destination_product.product_variations.create!(
          description: source_variation.description,
          safety_stock: source_variation.safety_stock,
        )
      end

      if source_product.foto.attached?
        destination_product.foto.attach(source_product.foto.blob) unless destination_product.foto.attached?
      end

      @summary[:destination_products_created] += 1
      @destination_products_cache[source_product.id] = destination_product
      destination_product
    end

    def find_destination_product_by_definition(source_product)
      normalized_description = source_product.descripcion.to_s.strip.downcase
      return nil if normalized_description.blank?

      scope = @destination_business.productos
               .where('LOWER(TRIM(productos.descripcion)) = ?', normalized_description)
               .where(presentation: source_product.presentation)

      if source_product.pack?
        scope = scope.where(cant_presentation: source_product.cant_presentation)
      end

      scope.order(:id).first
    end

    def sync_destination_variations!(destination_product:, source_product:)
      existing_by_name = destination_product.product_variations.index_by { |variation| variation.description.to_s.strip.downcase }

      source_product.product_variations.order(:id).each do |source_variation|
        normalized = source_variation.description.to_s.strip.downcase
        next if existing_by_name.key?(normalized)

        destination_product.product_variations.create!(
          description: source_variation.description,
          safety_stock: source_variation.safety_stock,
        )
      end
    end

    def create_destination_lot_from_source!(source_lot:, source_product:, destination_product:, quantity_to_transfer:)
      destination_lot = destination_product.stock_lots.create!(
        purchase_invoice_item: nil,
        supplier: nil,
        supplier_name: source_lot.supplier_name.presence || source_lot.supplier_display_name,
        description: absorbed_lot_description(source_lot),
        unit_cost_usd: source_lot.unit_cost_usd.to_d,
        quantity_in: quantity_to_transfer,
        quantity_remaining: quantity_to_transfer,
        purchased_at: source_lot.purchased_at || source_lot.created_at || Time.current,
      )

      source_rows = source_lot.stock_lot_variations.to_a
      return if source_rows.empty?

      variation_map = destination_product.product_variations.index_by { |variation| variation.description.to_s.strip.downcase }
      source_variation_map = source_product.product_variations.index_by(&:id)

      source_rows.each do |source_row|
        quantity = source_row.quantity_remaining.to_d
        next unless quantity.positive?

        source_row_description = source_row.variation_description.to_s.strip
        source_variation = source_variation_map[source_row.product_variation_id.to_i]
        source_variation_description = source_variation&.description.to_s.strip

        destination_variation = variation_map[source_row_description.downcase]
        if destination_variation.blank? && source_variation_description.present?
          destination_variation = variation_map[source_variation_description.downcase]
        end

        if destination_variation.blank?
          candidate_description = source_variation_description.presence || source_row_description.presence || 'Variacion'
          destination_variation = destination_product.product_variations.create!(
            description: candidate_description,
            safety_stock: source_variation&.safety_stock || 0,
          )
          variation_map[candidate_description.to_s.strip.downcase] = destination_variation
        end

        destination_lot.stock_lot_variations.create!(
          product_variation_id: destination_variation.id,
          variation_description: destination_variation.description,
          quantity_in: quantity,
          quantity_remaining: quantity,
        )
      end

      destination_lot.sync_quantity_remaining_from_variations! if destination_lot.stock_lot_variations.any?
    end

    def absorbed_lot_exists?(source_lot:, destination_product:)
      marker = absorbed_lot_marker(source_lot)
      destination_product.stock_lots.where(description: marker).exists?
    end

    def absorbed_lot_description(source_lot)
      absorbed_lot_marker(source_lot)
    end

    def absorbed_lot_marker(source_lot)
      "[ABSORB_STOCK][SRC_BIZ:#{@source_business.id}][SRC_PRODUCT:#{source_lot.producto_id}][SRC_LOT:#{source_lot.id}]"
    end

    def normalize_mode(mode)
      value = mode.to_s.strip
      return 'copy' if value == 'copy'

      'move'
    end

    def source_lot_transfer_units(source_lot)
      units_from_variations = source_lot.stock_lot_variations.sum { |row| row.quantity_remaining.to_d }
      return units_from_variations if units_from_variations.positive?

      lot_quantity_units(source_lot)
    end

    def lot_quantity_units(lot)
      quantity = lot.quantity_remaining.to_d
      item = lot.purchase_invoice_item
      return quantity if item.blank?
      return quantity if item.purchase_invoice&.intercompany?

      units_per_pack = item.unid_x_pack.to_d
      return quantity unless units_per_pack.positive?

      quantity * units_per_pack
    end
  end
end
