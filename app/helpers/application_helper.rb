module ApplicationHelper
  include Pagy::Frontend

  def truncated_name(name, length = 20, omission = '...')
    if name.length > length
      "#{name[0, length]}#{omission}"
    else
      name
    end
  end

  def format_money(value, unit: '', precision: 2)
    number_to_currency(
      value || 0,
      unit: unit,
      precision: precision,
      separator: ',',
      delimiter: '.',
      format: unit.present? ? "%u\u00A0%n" : '%n'
    )
  end

  def format_quantity(value, precision: 2)
    number_with_precision(
      value || 0,
      precision: precision,
      separator: ',',
      delimiter: '.',
      strip_insignificant_zeros: true
    )
  end

  def account_movement_display_description(movement)
    description = movement.description.to_s.strip
    return 'Sin descripción' if description.blank?

    formatted_debt_description = normalize_debt_movement_description(movement)
    return formatted_debt_description if formatted_debt_description.present?

    cleaned = description
          .gsub(/\s*\[(?:DEBT|DP|VENTA|VENTA_DRAFT|FACTURA_COMPRA|PURCHASE_INVOICE|GASTO|ACCOUNT|AM|CASH_SHIFT|CAMBIO_EFECTIVO):\d+\]/i, '')
              .gsub(/\s*\[LINE:[^\]]+\]/i, '')
              .gsub(/\s*\[COMMISSION\]/i, '')
              .gsub(/\s*-\s*Ref\s+[^\s\]]+/i, '')
    if description.match?(/CAMBIO_EFECTIVO/i) || description.match?(/cambio de efectivo/i)
      cleaned = cleaned.gsub(/\s*#\d+\b/, '')
    end
    cleaned = cleaned.gsub(/\s{2,}/, ' ').strip
    turno_match = cleaned.match(/^(.*\bcierre de turno\b)/i)
    return turno_match[1].strip if turno_match.present?

    cleaned
  end

  def account_movement_reference(movement)
    movement.reference.to_s.strip.presence || extract_movement_reference(movement.description)
  end

  def account_movement_source_link_data(movement)
    description = movement.description.to_s
    return nil if description.blank?

    if (cambio_id = extract_movement_source_id(description, 'CAMBIO_EFECTIVO')).present?
      cambio = current_business&.cambio_efectivos&.select(:id)&.find_by(id: cambio_id)
      return { label: 'Ver historial de ventas', path: historial_ventas_path } if cambio.present?
    end

    if (related_movement_id = extract_movement_source_id(description, 'AM')).present?
      related_movement = AccountMovement
                         .joins(:account)
                         .where(id: related_movement_id, accounts: { business_id: current_business&.id })
                         .select(:id, :account_id)
                         .first

      if related_movement.present?
        return {
          label: 'Ver movimiento relacionado',
          path: account_path(related_movement.account_id, movement_id: related_movement.id)
        }
      end
    end

    if (related_account_id = extract_movement_source_id(description, 'ACCOUNT')).present?
      related_account = current_business&.accounts&.select(:id)&.find_by(id: related_account_id)
      return { label: 'Ver cuenta relacionada', path: account_path(related_account) } if related_account.present?
    end

    if (cash_shift_id = extract_movement_source_id(description, 'CASH_SHIFT')).present?
      cash_shift = current_business&.cash_shifts&.select(:id)&.find_by(id: cash_shift_id)
      return { label: 'Ver turno', path: cash_shift_path(cash_shift) } if cash_shift.present?
    end

    if (debt_id = debt_source_id_for_description(description)).present?
      debt = current_business&.debts&.find_by(id: debt_id)
      if debt.present?
        if debt.service_cost_record? || description.match?(/\[SERVICE_COST\]/i)
          return {
            label: 'Ver registro de costo',
            path: pending_cost_detail_services_path(debt_id: debt.id)
          }
        end

        return { label: 'Ver registro de deuda', path: debt_path(debt) }
      end
    end

    if (sale_id = extract_movement_source_id(description, 'VENTA')).present?
      sale = current_business&.ventas&.select(:id)&.find_by(id: sale_id)
      return { label: 'Ver venta', path: venta_path(sale) } if sale.present?
    end

    invoice_id = extract_movement_source_id(description, 'FACTURA_COMPRA') ||
                 extract_movement_source_id(description, 'PURCHASE_INVOICE')
    if invoice_id.present?
      invoice = current_business&.purchase_invoices&.select(:id)&.find_by(id: invoice_id)
      return { label: 'Ver factura', path: purchase_invoice_path(invoice) } if invoice.present?
    end

    if (expense_id = extract_movement_source_id(description, 'GASTO')).present?
      expense = current_business&.expenses&.select(:id)&.find_by(id: expense_id)
      return { label: 'Ver gasto', path: expense_path(expense) } if expense.present?
    end

    nil
  end

  def manual_account_movement_editable?(movement)
    return false if movement.blank?
    return false if movement.account_settlement_id.present? || movement.cambio_efectivo_id.present?

    description = movement.description.to_s
    !description.match?(/\[(?:DEBT|DP|VENTA|VENTA_DRAFT|FACTURA_COMPRA|PURCHASE_INVOICE|GASTO|ACCOUNT|AM|CASH_SHIFT|CAMBIO_EFECTIVO):\d+\]/i)
  end

  def debt_display_description(value)
    raw_description = value.to_s.strip
    return 'Deuda sin descripcion' if raw_description.blank?

    if raw_description.match?(/\ACuota\s+Cashea\b/i)
      trimmed = raw_description.sub(/\s+pendiente\s+venta\s+#\d+.*\z/i, '')
      return trimmed.gsub(/\s{2,}/, ' ').strip.presence || 'Deuda sin descripcion'
    end

    cleaned = raw_description
              .gsub(/\s*\[(?:VENTA):\d+\]/i, '')
              .gsub(/\s*\[(?:CLIENTE_DUENO):[^\]]+\]/i, '')
    cleaned.gsub(/\s{2,}/, ' ').strip.presence || 'Deuda sin descripcion'
  end

  def debt_source_link_data(debt)
    description = debt&.description.to_s
    return nil if description.blank?

    sale_id = extract_movement_source_id(description, 'VENTA')
    return nil if sale_id.blank?

    sale = current_business&.ventas&.select(:id)&.find_by(id: sale_id)
    return nil if sale.blank?

    {
      label: "Ver venta ##{sale.id}",
      path: venta_path(sale)
    }
  end

  def debt_source_sale_id(debt)
    direct_sale_id = debt&.venta_id
    return direct_sale_id.to_i if direct_sale_id.present?

    description = debt&.description.to_s
    return nil if description.blank?

    tagged_sale_id = extract_movement_source_id(description, 'VENTA')
    return nil if tagged_sale_id.blank?

    sale = current_business&.ventas&.select(:id)&.find_by(id: tagged_sale_id)
    sale&.id
  end

  private

  def normalize_debt_movement_description(movement)
    description = movement.description.to_s
    action = detect_debt_movement_action(description)
    return nil if action.blank?

    payment = debt_payment_from_description(description)
    debt = payment&.debt || debt_from_description(description)
    return nil if debt.blank?

    cliente_name = debt.counterparty_display_name.to_s.strip.presence || 'Sin cliente'
    debt_description = if payment&.excess_payment?
                         'Excedente'
                       else
                         debt.description.to_s.strip.presence || 'Deuda sin descripcion'
                       end
    reference = account_movement_reference(movement)

    base = "#{action}: #{cliente_name} (#{debt_description})"
    return base if reference.blank?

    "#{base} - Ref #{reference}"
  end

  def detect_debt_movement_action(description)
    return 'Cobro de deuda' if description.to_s.match?(/\bCobro\s+(?:de\s+)?deuda\b/i)
    return 'Pago de deuda' if description.to_s.match?(/\bPago\s+(?:de\s+)?deuda\b/i)
    return 'Prestamo deuda' if description.to_s.match?(/\bPrestamo\s+deuda\b/i)

    nil
  end

  def extract_movement_reference(description)
    match = description.to_s.match(/(?:-|\s)Ref\s+([^\s\]]+)/i)
    match&.captures&.first
  end

  def debt_from_description(description)
    debt_id = debt_source_id_for_description(description)
    return nil if debt_id.blank?

    @movement_debt_cache ||= {}
    @movement_debt_cache[debt_id] ||= current_business&.debts&.find_by(id: debt_id)
  end

  def debt_source_id_for_description(description)
    direct_debt_id = extract_movement_source_id(description, 'DEBT')
    return direct_debt_id if direct_debt_id.present?

    payment = debt_payment_from_description(description)
    payment&.debt_id
  end

  def debt_payment_from_description(description)
    payment_id = extract_movement_source_id(description, 'DP')
    return nil if payment_id.blank?

    @movement_payment_cache ||= {}
    return @movement_payment_cache[payment_id] if @movement_payment_cache.key?(payment_id)

    @movement_payment_cache[payment_id] = DebtPayment
                                          .joins(:debt)
                                          .includes(:debt)
                                          .where(id: payment_id, debts: { business_id: current_business&.id })
                                          .first
  end

  def extract_movement_source_id(description, tag)
    match = description.to_s.match(/\[#{Regexp.escape(tag)}:(\d+)\]/i)
    match&.captures&.first&.to_i
  end
end
