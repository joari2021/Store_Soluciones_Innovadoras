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
    if purchase_invoice&.initial_inventory?
      unit_cost_usd = resolved_unit_cost_usd
      self.subtotal = unit_cost_usd * cantidad.to_d
    elsif purchase_invoice&.intercompany?
      self.subtotal = (costo_mayor || 0).to_d * intercompany_units_quantity
    else
      self.subtotal = (costo_mayor || 0) * (cantidad || 0)
    end
  end

  def line_subtotal_usd
    return costo_mayor.to_d * intercompany_units_quantity if purchase_invoice&.intercompany?
    return subtotal.to_d unless purchase_invoice&.initial_inventory?

    resolved_unit_cost_usd * cantidad.to_d
  end

  def line_subtotal_bs
    return costo_mayor_bs.to_d * intercompany_units_quantity if purchase_invoice&.intercompany?
    return costo_mayor_bs.to_d * cantidad.to_d unless purchase_invoice&.initial_inventory?

    rate = purchase_invoice&.tasa_dolar.to_d
    unit_cost_usd_rounded = resolved_unit_cost_usd.round(2)
    unit_cost_bs = unit_cost_usd_rounded * rate

    unit_cost_bs * cantidad.to_d
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

    if purchase_invoice&.intercompany?
      self.costo_menor = costo_mayor.to_d
      return
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
             when ActionController::Parameters
               raw_breakdown.to_unsafe_h.sort_by { |key, _| key.to_i }.map { |_, value| value }
             when Hash
               raw_breakdown.sort_by { |key, _| key.to_i }.map { |_, value| value }
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
    return stock_lot&.destroy unless purchase_invoice&.stock_delivered?

    lot = stock_lot || build_stock_lot
    initial_inventory = purchase_invoice&.initial_inventory?
    lot_quantity = purchase_invoice&.intercompany? ? intercompany_units_quantity : (cantidad || 0)
    lot.producto_id = producto_id
    lot.supplier_id = initial_inventory ? nil : purchase_invoice&.supplier_id
    lot.supplier_name = if initial_inventory
                          'Inventario inicial'
                        else
                          purchase_invoice&.supplier_name.presence || purchase_invoice&.supplier&.nombre || lot.supplier_name
                        end
    lot.description = initial_inventory ? 'inventario inicial' : nil
    lot.unit_cost_usd = resolved_unit_cost_usd
    lot.quantity_in = lot_quantity
    lot.quantity_remaining = lot_quantity if lot.new_record?
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
    total_units = total_units_for_variation_breakdown
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
        if variation_description.blank? && single_variation.present?
          variation_description = single_variation&.description.to_s.strip
        end

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
    return cantidad.to_d if purchase_invoice&.initial_inventory?
    return intercompany_units_quantity if purchase_invoice&.intercompany?

    units_per_pack = unid_x_pack.to_d
    cantidad.to_d * (units_per_pack.positive? ? units_per_pack : 1)
  end

  def intercompany_units_quantity
    units = unid_x_pack.to_d
    units.positive? ? units : cantidad.to_d
  end

  def resolved_unit_cost_usd
    units_per_pack = unid_x_pack.to_d
    unit_cost_source = costo_mayor.to_d

    if !purchase_invoice&.initial_inventory? && !exento?
      unit_cost_source = (unit_cost_source * 1.16.to_d).round(8)
    end

    return unit_cost_source if purchase_invoice&.intercompany?
    return unit_cost_source if units_per_pack <= 0

    unit_cost_source / units_per_pack
  end
end
