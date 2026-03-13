module ServicesHelper
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

        [
          "#{product.descripcion} ($#{format_quantity(price_usd)})",
          product.id,
          {
            data: {
              price_usd: price_usd.to_f,
              price_bs: price_bs.to_f
            }
          }
        ]
      end,
      selected_id
    )
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
