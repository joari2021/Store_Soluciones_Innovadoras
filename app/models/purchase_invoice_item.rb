class PurchaseInvoiceItem < ApplicationRecord
  self.table_name = 'factura_items'

  belongs_to :purchase_invoice, class_name: 'PurchaseInvoice', foreign_key: :factura_id,
                                inverse_of: :purchase_invoice_items
  belongs_to :producto, optional: true
  has_one :stock_lot, class_name: 'StockLot', foreign_key: :factura_item_id, inverse_of: :purchase_invoice_item,
                      dependent: :destroy

  before_validation :set_product_name
  before_validation :normalize_costs_for_currency_priority
  before_validation :normalize_variation_breakdown
  before_validation :calcular_subtotal
  after_commit :sync_stock_lot, on: %i[create update]

  def set_product_name
    self.product_name = producto&.descripcion if product_name.blank?
  end

  def calcular_subtotal
    self.subtotal = (costo_mayor || 0) * (cantidad || 0)
  end

  private

  def normalize_costs_for_currency_priority
    rate = purchase_invoice&.tasa_dolar.to_d
    priority = purchase_invoice&.supplier&.pricing_currency_priority.presence || 'usd'

    usd_value = costo_mayor.to_d
    bs_value = costo_mayor_bs.to_d

    if priority == 'bs'
      if bs_value.positive?
        self.costo_mayor = rate.positive? ? (bs_value / rate) : usd_value
      elsif usd_value.positive?
        self.costo_mayor_bs = usd_value * rate
      end
    elsif usd_value.positive?
      self.costo_mayor_bs = usd_value * rate
    elsif bs_value.positive? && rate.positive?
      self.costo_mayor = bs_value / rate
    end

    unidades = unid_x_pack.to_d
    return unless unidades.positive?

    self.costo_menor = costo_mayor.to_d / unidades
  end

  def normalize_variation_breakdown
    raw_breakdown = variation_breakdown
    parsed = case raw_breakdown
             when String
               begin
                 JSON.parse(raw_breakdown)
               rescue StandardError
                 []
               end
             when Array
               raw_breakdown
             else
               []
             end

    single_variation = single_product_variation

    rows = parsed.filter_map do |entry|
      next unless entry.is_a?(Hash)

      quantity = (entry['quantity'] || entry[:quantity]).to_d
      next if quantity <= 0

      variation_id_raw = entry['variation_id'] || entry[:variation_id]
      variation_id = variation_id_raw.to_i
      variation_id = nil unless variation_id.positive?
      variation_id = single_variation&.id if variation_id.blank? && single_variation.present?

      description = (entry['description'] || entry[:description]).to_s.strip
      description = single_variation&.description.to_s.strip if description.blank? && single_variation.present?

      {
        'variation_id' => variation_id,
        'description' => description.presence || 'Variación',
        'quantity' => quantity.to_f
      }
    end

    if rows.empty? && single_variation.present?
      total_units = total_units_for_variation_breakdown
      if total_units.positive?
        rows = [{
          'variation_id' => single_variation.id,
          'description' => single_variation.description,
          'quantity' => total_units.to_f
        }]
      end
    end

    self.variation_breakdown = rows
    self.variacion_nombre = if rows.empty?
                              nil
                            else
                              rows.map do |row|
                                "#{row['description'].presence || 'Variación'}: #{row['quantity']}"
                              end.join(' | ')
                            end
  end

  def sync_stock_lot
    return stock_lot&.destroy if producto_id.blank?

    lot = stock_lot || build_stock_lot
    lot.producto_id = producto_id
    lot.supplier_id = purchase_invoice&.supplier_id
    lot.supplier_name = purchase_invoice&.supplier_name.presence || purchase_invoice&.supplier&.nombre || lot.supplier_name
    lot.unit_cost_usd = costo_menor || 0
    lot.quantity_in = cantidad || 0
    lot.quantity_remaining = cantidad || 0 if lot.new_record?
    lot.purchased_at = purchase_invoice&.fecha_emision || purchase_invoice&.created_at || Time.current
    lot.save!

    sync_stock_lot_variations!(lot)
  end

  def sync_stock_lot_variations!(lot)
    rows = build_variation_stock_rows
    existing_rows = lot.stock_lot_variations.index_by do |entry|
      variation_row_key(entry.product_variation_id, entry.variation_description)
    end
    used_keys = []

    rows.each do |row|
      key = variation_row_key(row[:product_variation_id], row[:variation_description])
      used_keys << key

      record = existing_rows[key] || lot.stock_lot_variations.build(
        product_variation_id: row[:product_variation_id],
        variation_description: row[:variation_description]
      )

      previous_in = record.quantity_in.to_d
      previous_remaining = record.quantity_remaining.to_d
      consumed = [previous_in - previous_remaining, 0.to_d].max

      record.product_variation_id = row[:product_variation_id]
      record.variation_description = row[:variation_description]
      record.quantity_in = row[:quantity_in]
      record.quantity_remaining = [row[:quantity_in] - consumed, 0.to_d].max
      record.save!
    end

    lot.stock_lot_variations.each do |entry|
      key = variation_row_key(entry.product_variation_id, entry.variation_description)
      next if used_keys.include?(key)

      consumed = entry.quantity_in.to_d - entry.quantity_remaining.to_d
      if consumed <= 0
        entry.destroy!
      else
        entry.quantity_in = entry.quantity_remaining
        entry.save!
      end
    end

    lot.sync_quantity_remaining_from_variations!
  end

  def build_variation_stock_rows
    units_per_pack = unid_x_pack.to_d
    total_units = cantidad.to_d * (units_per_pack.positive? ? units_per_pack : 1)
    rows = []
    single_variation = single_product_variation

    if variation_breakdown.is_a?(Array) && variation_breakdown.any?
      rows = variation_breakdown.filter_map do |entry|
        next unless entry.is_a?(Hash)

        quantity = (entry['quantity'] || entry[:quantity]).to_d
        next if quantity <= 0

        variation_id_raw = entry['variation_id'] || entry[:variation_id]
        variation_id = variation_id_raw.to_i
        variation_id = nil unless variation_id.positive?
        variation_id = single_variation&.id if variation_id.blank? && single_variation.present?

        variation_description = (entry['description'] || entry[:description]).to_s.strip
        variation_description = single_variation&.description.to_s.strip if variation_description.blank? && single_variation.present?

        {
          product_variation_id: variation_id,
          variation_description: variation_description.presence || 'Variación',
          quantity_in: quantity
        }
      end
    end

    if rows.empty?
      rows = [{
        product_variation_id: single_variation&.id,
        variation_description: single_variation&.description.presence || variacion_nombre.presence || 'Unica',
        quantity_in: total_units
      }]
    end

    rows
      .group_by { |row| variation_row_key(row[:product_variation_id], row[:variation_description]) }
      .values
      .map do |entries|
        sample = entries.first
        {
          product_variation_id: sample[:product_variation_id],
          variation_description: sample[:variation_description],
          quantity_in: entries.sum { |entry| entry[:quantity_in].to_d }
        }
      end
  end

  def variation_row_key(variation_id, description)
    "#{variation_id.presence || 'none'}::#{description.to_s.strip.downcase}"
  end

  def single_product_variation
    return nil unless producto

    variations = producto.product_variations.order(:id).to_a
    return nil unless variations.one?

    variations.first
  end

  def total_units_for_variation_breakdown
    units_per_pack = unid_x_pack.to_d
    cantidad.to_d * (units_per_pack.positive? ? units_per_pack : 1)
  end
end
