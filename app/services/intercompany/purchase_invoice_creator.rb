module Intercompany
  class PurchaseInvoiceCreator
    Result = Struct.new(:success?, :invoice, :errors)

    def initialize(current_business:, source_business:, purchase_invoice:, payment_context:, source_account:, current_user:)
      @current_business = current_business
      @source_business = source_business
      @purchase_invoice = purchase_invoice
      @payment_context = payment_context
      @source_account = source_account
      @current_user = current_user
      @cloned_products_cache = {}
    end

    def call
      errors = []

      ActiveRecord::Base.transaction do
        prepare_intercompany_invoice!
        normalize_items_from_source!

        if @purchase_invoice.errors.any?
          errors.concat(@purchase_invoice.errors.full_messages)
          raise ActiveRecord::Rollback
        end

        @purchase_invoice.save!

        payment_entries = Array(@payment_context[:payments])
        register_buyer_outgoing_movements!(payment_entries)
        register_source_incoming_movements!(payment_entries)
        create_mirror_pending_debts!
      end

      if @purchase_invoice.persisted? && errors.empty?
        Result.new(true, @purchase_invoice, [])
      else
        errors = @purchase_invoice.errors.full_messages if errors.empty?
        Result.new(false, @purchase_invoice, errors)
      end
    rescue ActiveRecord::RecordInvalid => e
      message = if e.record.respond_to?(:errors) && e.record.errors.any?
          e.record.errors.full_messages
        else
          [e.message]
        end
      Result.new(false, @purchase_invoice, message)
    end

    private

    def prepare_intercompany_invoice!
      @purchase_invoice.intercompany = true
      @purchase_invoice.source_business = @source_business
      @purchase_invoice.supplier = nil
      @purchase_invoice.supplier_name = @source_business.name
    end

    def normalize_items_from_source!
      items = @purchase_invoice.purchase_invoice_items.reject(&:marked_for_destruction?)
      if items.empty?
        @purchase_invoice.errors.add(:base, "Debes agregar al menos un producto para la factura inter-empresas.")
        return
      end

      items.each do |item|
        source_product = @source_business.productos.includes(:product_variations, :stock_lots).find_by(id: item.producto_id)
        unless source_product
          @purchase_invoice.errors.add(:base, "Producto origen ##{item.producto_id} no existe en el negocio que surte.")
          next
        end

        destination_product = clone_or_find_destination_product!(source_product)
        normalized_rows = normalize_variation_rows!(item: item, source_product: source_product,
                                                    destination_product: destination_product)
        next if normalized_rows.blank?

        weighted_unit_cost = weighted_unit_cost_from_source!(source_product: source_product, rows: normalized_rows)
        next if weighted_unit_cost.nil?

        total_units = normalized_rows.sum { |row| row[:quantity].to_d }

        item.producto = destination_product
        item.product_name = destination_product.descripcion
        item.cantidad = total_units
        item.unid_x_pack = 1
        item.costo_mayor = weighted_unit_cost
        item.costo_menor = weighted_unit_cost
        item.costo_mayor_bs = weighted_unit_cost * @purchase_invoice.tasa_dolar.to_d
        item.exento = true
        item.variation_breakdown = normalized_rows.map do |row|
          {
            "variation_id" => row[:destination_variation_id],
            "description" => row[:description],
            "quantity" => row[:quantity].to_d.to_f,
          }
        end
      end
    end

    def clone_or_find_destination_product!(source_product)
      cache_key = source_product.id
      return @cloned_products_cache[cache_key] if @cloned_products_cache.key?(cache_key)

      destination_product = @current_business.productos.find_by(
        source_business_id: @source_business.id,
        source_product_id: source_product.id,
      )

      if destination_product.blank?
        destination_product = find_existing_destination_product_by_definition(source_product)
        if destination_product.present? && destination_product.source_business_id.blank? && destination_product.source_product_id.blank?
          destination_product.update!(
            source_business_id: @source_business.id,
            source_product_id: source_product.id,
          )
        end
      end

      unless destination_product
        destination_categoria = @current_business.categorias.find_or_create_by!(
          nombre: source_product.categoria&.nombre.presence || "General",
        )

        preset = nil
        if source_product.profit_margin_preset.present?
          preset = @current_business.profit_margin_presets.find_or_create_by!(
            percentage: source_product.profit_margin_preset.percentage,
          )
        end

        destination_product = @current_business.productos.create!(
          descripcion: source_product.descripcion,
          presentation: source_product.presentation,
          cant_presentation: source_product.cant_presentation,
          allow_unpack: source_product.allow_unpack,
          precio_venta_usd: source_product.precio_venta_usd,
          porcentaje_ganancia: source_product.porcentaje_ganancia,
          categoria: destination_categoria,
          profit_margin_preset: preset,
          exento: source_product.respond_to?(:exento) ? source_product.exento : false,
          source_business_id: @source_business.id,
          source_product_id: source_product.id,
        )

        destination_product.product_variations.destroy_all
        source_product.product_variations.order(:id).find_each do |variation|
          destination_product.product_variations.create!(
            description: variation.description,
            safety_stock: variation.safety_stock,
          )
        end
      end

      @cloned_products_cache[cache_key] = destination_product
    end

    def find_existing_destination_product_by_definition(source_product)
      normalized_description = normalize_product_description(source_product.descripcion)
      return nil if normalized_description.blank?

      current_scope = @current_business.productos
                                     .where('LOWER(TRIM(productos.descripcion)) = ?', normalized_description)
                                     .where(presentation: source_product.presentation)

      if source_product.pack?
        current_scope = current_scope.where(cant_presentation: source_product.cant_presentation)
      end

      candidates = current_scope.to_a
      return nil if candidates.blank?

      candidates.find do |candidate|
        same_mapping = candidate.source_business_id == @source_business.id && candidate.source_product_id == source_product.id
        unmapped = candidate.source_business_id.blank? && candidate.source_product_id.blank?
        same_mapping || unmapped
      end
    end

    def normalize_product_description(raw_value)
      raw_value.to_s.strip.downcase
    end

    def normalize_variation_rows!(item:, source_product:, destination_product:)
      source_variations = source_product.product_variations.order(:id).to_a
      destination_variations = destination_product.product_variations.order(:id).to_a
      destination_by_desc = destination_variations.index_by { |variation| variation.description.to_s.strip.downcase }

      raw_rows = item.variation_breakdown.is_a?(Array) ? item.variation_breakdown : []
      rows = raw_rows.filter_map do |row|
        quantity = row_quantity(row)
        next if quantity <= 0

        source_variation = find_source_variation(source_product: source_product, source_variations: source_variations, row: row)
        if source_variation.blank?
          @purchase_invoice.errors.add(:base,
                                       "No se pudo resolver la variacion del producto #{source_product.descripcion}.")
          next
        end

        destination_variation = destination_by_desc[source_variation.description.to_s.strip.downcase]
        if destination_variation.blank?
          destination_variation = destination_product.product_variations.create!(
            description: source_variation.description,
            safety_stock: source_variation.safety_stock,
          )
          destination_by_desc[source_variation.description.to_s.strip.downcase] = destination_variation
        end

        {
          source_variation_id: source_variation.id,
          destination_variation_id: destination_variation.id,
          description: source_variation.description,
          quantity: quantity,
        }
      end

      if rows.empty? && source_variations.one?
        source_variation = source_variations.first
        destination_variation = destination_by_desc[source_variation.description.to_s.strip.downcase]
        quantity = item.cantidad.to_d
        rows = [{
          source_variation_id: source_variation.id,
          destination_variation_id: destination_variation.id,
          description: source_variation.description,
          quantity: quantity,
        }]
      end

      rows
    end

    def weighted_unit_cost_from_source!(source_product:, rows:)
      total_cost = 0.to_d
      total_units = 0.to_d

      rows.each do |row|
        quantity = row[:quantity].to_d
        allocations = consume_source_variation!(source_product: source_product,
                                                source_variation_id: row[:source_variation_id],
                                                quantity: quantity)
        return nil if allocations.nil?

        allocations.each do |allocation|
          total_cost += allocation[:quantity].to_d * allocation[:unit_cost_usd].to_d
          total_units += allocation[:quantity].to_d
        end
      end

      return nil unless total_units.positive?

      (total_cost / total_units).round(8)
    end

    def consume_source_variation!(source_product:, source_variation_id:, quantity:)
      remaining = quantity.to_d
      rows_scope = StockLotVariation
        .joins(:stock_lot)
        .where(stock_lot_variations: { product_variation_id: source_variation_id })
        .where(stock_lots: { producto_id: source_product.id })
        .where("stock_lot_variations.quantity_remaining > 0")
        .order(Arel.sql("stock_lots.unit_cost_usd DESC, stock_lots.purchased_at ASC, stock_lots.created_at ASC"))

      available = rows_scope.sum(:quantity_remaining).to_d
      if available < remaining
        @purchase_invoice.errors.add(:base,
                                     "Stock insuficiente en origen para #{source_product.descripcion}. Disponible: #{available.to_f.round(2)}")
        return nil
      end

      allocations = []

      rows_scope.each do |variation_row|
        break if remaining <= 0

        variation_row.lock!
        lot = variation_row.stock_lot
        available_in_row = variation_row.quantity_remaining.to_d
        next if available_in_row <= 0

        consumed = [available_in_row, remaining].min
        variation_row.update!(quantity_remaining: available_in_row - consumed)
        lot.sync_quantity_remaining_from_variations!

        allocations << {
          quantity: consumed,
          unit_cost_usd: lot.unit_cost_usd.to_d,
        }

        remaining -= consumed
      end

      allocations
    end

    def register_buyer_outgoing_movements!(payment_entries)
      occurred_at = @purchase_invoice.fecha_emision.presence || Time.current
      description = "Pago factura inter-empresa ##{@purchase_invoice.id} a #{@source_business.name} [FACTURA_COMPRA:#{@purchase_invoice.id}]"

      payment_entries.each do |entry|
        account = entry[:account]
        amount = entry[:amount].to_d
        next unless account.present? && amount.positive?

        attrs = {
          movement_kind: "expense",
          amount: amount,
          description: description,
          occurred_at: occurred_at,
        }
        attrs[:payment_method] = "transfer" if account.account_type == "bank_account"
        account.account_movements.create!(attrs)
      end
    end

    def register_source_incoming_movements!(payment_entries)
      return if @source_account.blank?

      total_amount = payment_entries.sum { |entry| entry[:amount].to_d }.round(2)
      return unless total_amount.positive?

      occurred_at = @purchase_invoice.fecha_emision.presence || Time.current
      @source_account.account_movements.create!(
        movement_kind: "income",
        amount: total_amount,
        description: "Cobro factura inter-empresa ##{@purchase_invoice.id} desde #{@current_business.name} [FACTURA_COMPRA_MIRROR:#{@purchase_invoice.id}]",
        occurred_at: occurred_at,
        payment_method: (@source_account.account_type == "bank_account" ? "transfer" : nil),
      )
    end

    def create_mirror_pending_debts!
      pending_amount_bs = @payment_context[:pending_amount_bs].to_d.round(2)
      return unless pending_amount_bs.positive?

      invoice_reference = @purchase_invoice.numero.to_s.strip.presence || "##{@purchase_invoice.id}"
      issued_on = @purchase_invoice.fecha_emision&.to_date || Date.current
      due_on = @payment_context[:pending_due_on]

      payable = @current_business.debts.create!(
        debt_kind: "payable",
        name: @source_business.name,
        description: "Saldo pendiente factura inter-empresa #{invoice_reference} [FACTURA_COMPRA:#{@purchase_invoice.id}] [IC_MIRROR]",
        amount: pending_amount_bs,
        currency: "VES",
        issued_on: issued_on,
        due_on: due_on,
        mirror_sync_enabled: true,
        mirror_account: @source_account,
      )

      source_destination_account = buyer_default_account_for_mirror

      receivable = @source_business.debts.create!(
        debt_kind: "receivable",
        name: @current_business.name,
        description: "Cuenta por cobrar factura inter-empresa #{invoice_reference} [FACTURA_COMPRA_MIRROR:#{@purchase_invoice.id}] [IC_MIRROR]",
        amount: pending_amount_bs,
        currency: "VES",
        issued_on: issued_on,
        due_on: due_on,
        mirror_sync_enabled: true,
        mirror_account: source_destination_account,
      )

      payable.update!(mirror_debt: receivable)
      receivable.update!(mirror_debt: payable)
    end

    def buyer_default_account_for_mirror
      payment_entry = Array(@payment_context[:payments]).find { |entry| entry[:account].present? }
      payment_entry&.dig(:account)
    end

    def find_source_variation(source_product:, source_variations:, row:)
      variation_id = row["variation_id"] || row[:variation_id]
      if variation_id.present?
        variation = source_variations.find { |entry| entry.id == variation_id.to_i }
        return variation if variation.present?
      end

      description = (row["description"] || row[:description]).to_s.strip.downcase
      if description.present?
        variation = source_variations.find { |entry| entry.description.to_s.strip.downcase == description }
        return variation if variation.present?
      end

      source_variations.one? ? source_variations.first : nil
    end

    def row_quantity(row)
      raw_quantity = row["quantity"] || row[:quantity]
      raw_quantity.to_d
    end
  end
end
