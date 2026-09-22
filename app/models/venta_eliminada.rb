class VentaEliminada < ApplicationRecord
  self.table_name = 'venta_eliminadas'

  belongs_to :business
  belongs_to :venta, optional: true
  belongs_to :seller_user, class_name: 'User', optional: true
  belongs_to :cashier_user, class_name: 'User', optional: true
  belongs_to :cliente, optional: true
  belongs_to :deleted_by_user, class_name: 'User', optional: true

  validates :business_id, presence: true
  validates :deleted_at, presence: true

  def sale_data
    return {} unless payload.is_a?(Hash)

    payload['venta'].is_a?(Hash) ? payload['venta'] : {}
  end

  def sale_items
    items = payload.is_a?(Hash) ? payload['items'] : nil
    return items if items.is_a?(Array)

    nested_items = sale_data['venta_items']
    nested_items.is_a?(Array) ? nested_items : []
  end

  def sale_payments
    payments = payload.is_a?(Hash) ? payload['payments'] : nil
    return payments if payments.is_a?(Array)

    nested_payments = sale_data['venta_payments']
    nested_payments.is_a?(Array) ? nested_payments : []
  end

  def cliente_display_name
    cliente&.name.to_s.strip.presence || sale_data.dig('cliente', 'name').to_s.strip.presence || 'Cliente general'
  end

  def seller_display_name
    seller_user&.display_name.to_s.strip.presence || sale_data.dig('user', 'display_name').to_s.strip.presence || 'Sin vendedor'
  end

  def cashier_display_name
    cashier_user&.display_name.to_s.strip.presence || sale_data.dig('cashier_user', 'display_name').to_s.strip.presence || 'Sin cajero'
  end

  def deleted_by_display_name
    deleted_by_user&.display_name.to_s.strip.presence || 'Sin usuario'
  end

  def sale_status_label
    status_value = sale_data['status'].to_s
    Venta::STATUSES[status_value] || status_value.humanize
  end

  def sale_currency_label
    currency_value = sale_data['base_currency'].to_s.upcase
    Venta::BASE_CURRENCIES[currency_value] || currency_value.presence || 'No indicada'
  end

  def sale_created_at_label
    raw_value = sale_data['created_at']
    return 'No disponible' if raw_value.blank?

    Time.zone.parse(raw_value.to_s).in_time_zone('America/Caracas').strftime('%d/%m/%Y %H:%M')
  rescue ArgumentError, TypeError
    raw_value.to_s
  end

  def item_display_name(item)
    row = item.respond_to?(:to_h) ? item.to_h : {}
    base_name = row['product_name'].to_s.strip
    base_name = row['service_name'].to_s.strip if base_name.blank?
    base_name = row['name'].to_s.strip if base_name.blank?
    base_name = row['description'].to_s.strip if base_name.blank?
    base_name = 'Ítem' if base_name.blank?

    variation_name = row['variation_name'].to_s.strip
    variation_name = row['product_variation_name'].to_s.strip if variation_name.blank?
    variation_name.present? ? "#{base_name} (#{variation_name})" : base_name
  end

  def payment_method_label(payment)
    row = payment.respond_to?(:to_h) ? payment.to_h : {}
    method = row['payment_method'].to_s
    VentaPayment::METHODS[method] || method.humanize
  end

  def payment_kind_label(payment)
    row = payment.respond_to?(:to_h) ? payment.to_h : {}
    kind = row['payment_kind'].to_s
    VentaPayment::PAYMENT_KINDS[kind] || kind.humanize
  end

  def payment_reference(payment)
    row = payment.respond_to?(:to_h) ? payment.to_h : {}
    row['reference'].to_s.strip.presence || 'Sin referencia'
  end

  def payment_date_label(payment)
    row = payment.respond_to?(:to_h) ? payment.to_h : {}
    raw_date = row['payment_date'].presence || row['created_at'].presence
    return 'Sin fecha' if raw_date.blank?

    Time.zone.parse(raw_date.to_s).strftime('%d/%m/%Y') rescue raw_date.to_s
  end
end
