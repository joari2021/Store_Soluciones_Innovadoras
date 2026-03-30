module ServicesHelper
  def service_reference_name(service)
    reference = service.currency_base_price.to_s.strip
    reference = 'Dolar BCV' if reference == '$'
    reference.presence || 'Dolar BCV'
  end

  def service_reference_amount(service)
    amount = service.sale_price.to_d
    return amount if amount.positive?

    reference = service_reference_name(service)
    return service.value_units.to_d if reference == 'Unidad VI' && service.value_units.to_d.positive?

    amount
  end

  def service_primary_price_label(service, tasa_dolar:, unidad_vi:)
    reference = service_reference_name(service)
    amount = if reference == 'Unidad VI'
               service.unit_price_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi).to_d
             else
               service_reference_amount(service)
             end
    return nil unless amount.positive?

    symbol = if reference == 'Bs' || reference == 'Unidad VI'
               'Bs'
             else
               TasaCambio.latest_symbol(reference) || TasaCambio::DEFAULT_SYMBOLS[reference] || reference
             end

    format_money(amount, unit: "#{symbol} ")
  end

  def service_reference_price_label(service, tasa_dolar:, unidad_vi:)
    reference = service_reference_name(service)

    if reference == 'Bs'
      usd_amount = service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
      return nil unless usd_amount.to_d.positive?

      return "Ref: #{format_money(usd_amount, unit: '$ ')}"
    end

    if reference == 'Dolar BCV' || reference == 'Euro BCV' || reference == 'USDT'
      bs_amount = service.unit_price_bs(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
      return nil unless bs_amount.to_d.positive?

      return "Ref: #{format_money(bs_amount, unit: 'Bs ')}"
    end

    if reference == 'Unidad VI'
      usd_amount = service.unit_price_usd(tasa_dolar: tasa_dolar, unidad_vi: unidad_vi)
      return nil unless usd_amount.to_d.positive?

      return "Ref: #{format_money(usd_amount, unit: '$ ')}"
    end

    nil
  end

  def link_to_add_service_managers(name, m, association)
    new_object = m.object.send(association).klass.new
    id = new_object.object_id
    fields = m.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + '_fields', m: builder)
    end
    link_to(name, '#',
            class: 'inline-flex items-center gap-2 rounded-xl bg-sky-100 px-3 py-2 text-xs font-semibold text-sky-700 hover:bg-sky-200', id: 'add_fields_service_managers', data: { id: id, fields: fields.gsub("\n", '') })
  end

  def nested_services_options_for_select(services:, bcv_rate:, selected_id: nil)
    options_for_select(
      services.map do |service|
        unit_usd = service.unit_price_usd(tasa_dolar: bcv_rate).to_d
        unit_bs = service.unit_price_bs(tasa_dolar: bcv_rate).to_d
        system_name = service.system_service&.name.to_s
        label_suffix = system_name.present? ? " - #{system_name}" : ''
        [
          "#{service.description}#{label_suffix}",
          service.id,
          {
            data: {
              pricing_mode: service.pricing_mode,
              to_agree: service.to_agree?,
              price_usd: unit_usd.to_f,
              price_bs: unit_bs.to_f
            }
          }
        ]
      end,
      selected_id
    )
  end

  def products_options_for_select(products:, bcv_rate:, selected_id: nil)
    rate = bcv_rate.to_d

    options_for_select(
      products.map do |product|
        price_usd = product.precio_venta_usd.to_d
        price_bs = rate.positive? ? (price_usd * rate).round(2) : 0.to_d
        variations_payload = product
                             .product_variations
                             .sort_by(&:id)
                             .map do |variation|
                               {
                                 id: variation.id,
                                 description: variation.description.to_s
                               }
        end
        oldest_active_lot = product.stock_lots
                                 .ordered_fifo
                                 .find { |lot| lot.quantity_remaining.to_d.positive? }
        oldest_lot_cost_usd = oldest_active_lot&.unit_cost_usd.to_d
        oldest_lot_cost_bs = rate.positive? ? (oldest_lot_cost_usd * rate).round(2) : 0.to_d

        [
          "#{product.descripcion} ($#{format_quantity(price_usd)})",
          product.id,
          {
            data: {
              price_usd: price_usd.to_f,
              price_bs: price_bs.to_f,
              variations: variations_payload.to_json,
              oldest_lot_cost_usd: oldest_lot_cost_usd.to_f,
              oldest_lot_cost_bs: oldest_lot_cost_bs.to_f
            }
          }
        ]
      end,
      selected_id
    )
  end

  def product_variation_options_for_select(product:, selected_id: nil)
    return options_for_select([], selected_id) unless product

    variations = product.product_variations.order(:id).map do |variation|
      [variation.description.to_s, variation.id]
    end

    options_for_select(variations, selected_id)
  end

  def currency_reference_options_for_select(rows:, selected: nil)
    options_for_select(
      rows.map do |row|
        [
          "#{row[:label]} (#{row[:symbol]})",
          row[:value],
          {
            data: {
              money_symbol: row[:symbol],
              rate_bs: row[:rate_bs].to_d.to_s('F'),
              currency_name: row[:label]
            }
          }
        ]
      end,
      selected
    )
  end

  def currency_symbol_for_reference(reference, rows:, fallback: '$')
    rows.find { |row| row[:value].to_s == reference.to_s }&.dig(:symbol) || fallback
  end

  def expense_reference_for_form(expense, rows:)
    persisted_reference = expense.try(:currency_reference).to_s.strip
    return persisted_reference if persisted_reference.present?

    if expense.amount_bs.to_d.positive? && expense.amount_usd.to_d.zero?
      'Bs'
    elsif rows.any? { |row| row[:value] == 'Dolar BCV' }
      'Dolar BCV'
    else
      rows.first&.dig(:value).to_s
    end
  end

  def expense_reference_amount_for_form(expense, reference:)
    amount_reference = expense.try(:amount_reference).to_d
    return amount_reference if amount_reference.positive?

    reference.to_s == 'Bs' ? expense.amount_bs.to_d : expense.amount_usd.to_d
  end

  def plain_decimal_input_value(value, default: nil)
    amount = value.presence&.to_d

    amount = default.to_d if default.present? && (!amount || amount <= 0)

    return '' unless amount

    amount = 0.to_d if amount.negative?
    return amount.to_i.to_s if amount == amount.to_i

    amount.to_s('F').sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\\1')
  end
end
