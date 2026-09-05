class PurchaseInvoice < ApplicationRecord
  self.table_name = "facturas"

  INVOICE_KIND_PURCHASE = "purchase".freeze
  INVOICE_KIND_INITIAL_INVENTORY = "initial_inventory".freeze
  INVOICE_KINDS = [INVOICE_KIND_PURCHASE, INVOICE_KIND_INITIAL_INVENTORY].freeze

  belongs_to :business
  belongs_to :supplier, optional: true
  belongs_to :source_business, class_name: "Business", optional: true
  has_many :purchase_invoice_items, lambda {
    order(created_at: :asc, id: :asc)
  }, class_name: "PurchaseInvoiceItem", foreign_key: :factura_id, dependent: :destroy, inverse_of: :purchase_invoice
  has_many :productos, through: :purchase_invoice_items

  accepts_nested_attributes_for :purchase_invoice_items, allow_destroy: true

  validates :supplier, presence: true, unless: :supplier_optional?
  validates :source_business, presence: true, if: :intercompany?
  validate :source_business_differs_from_destination, if: :intercompany?
  validates :invoice_kind, presence: true, inclusion: { in: INVOICE_KINDS }
  validate :single_initial_inventory_per_business
  validate :prevent_undeliver_when_stock_consumed

  before_validation :normalize_invoice_kind
  before_validation :normalize_delivered
  before_validation :set_supplier_name_snapshot
  before_save :calcular_monto_total
  after_save :sync_items_stock_lots_for_delivery_change, on: :update

  scope :initial_inventory, -> { where(invoice_kind: INVOICE_KIND_INITIAL_INVENTORY) }

  def initial_inventory?
    invoice_kind == INVOICE_KIND_INITIAL_INVENTORY
  end

  def intercompany?
    ActiveModel::Type::Boolean.new.cast(self[:intercompany]) || source_business_id.present?
  end

  def kind_label
    initial_inventory? ? "Inventario inicial" : "Factura de compra"
  end

  def supplier_display_name
    supplier_name.presence || supplier&.nombre || "Proveedor"
  end

  def stock_delivered?
    initial_inventory? || ActiveModel::Type::Boolean.new.cast(self[:delivered])
  end

  def total_bs
    totals_breakdown[:total_bs].round(4)
  end

  def calcular_monto_total
    totals = totals_breakdown

    priority = supplier&.pricing_currency_priority.presence || "usd"
    rate = tasa_dolar.to_d
    total_usd = if priority == "bs"
        rate.positive? ? (totals[:total_bs] / rate) : totals[:total_usd]
      else
        totals[:total_usd]
      end

    self.monto_total = total_usd.round(4)
  end

  def set_supplier_name_snapshot
    self.supplier_name = supplier&.nombre if supplier_name.blank? && supplier.present?
  end

  def totals_breakdown
    active_items = purchase_invoice_items.reject(&:marked_for_destruction?)

    if initial_inventory?
      total_usd = active_items.sum { |item| item.line_subtotal_usd.to_d }
      total_bs = active_items.sum { |item| item.line_subtotal_bs.to_d }

      return {
               subtotal_usd: 0.to_d,
               subtotal_bs: 0.to_d,
               exento_usd: total_usd,
               exento_bs: total_bs,
               iva_usd: 0.to_d,
               iva_bs: 0.to_d,
               descuento_usd: 0.to_d,
               descuento_bs: 0.to_d,
               total_usd: total_usd,
               total_bs: total_bs,
             }
    end

    subtotal_usd = 0.to_d
    subtotal_bs = 0.to_d
    exento_usd = 0.to_d
    exento_bs = 0.to_d

    active_items.each do |item|
      line_usd = item.line_subtotal_usd.to_d
      line_bs = item.line_subtotal_bs.to_d

      if item.exento?
        exento_usd += line_usd
        exento_bs += line_bs
      else
        subtotal_usd += line_usd
        subtotal_bs += line_bs
      end
    end

    iva_usd = subtotal_usd * 0.16
    iva_bs = subtotal_bs * 0.16
    gross_total_usd = subtotal_usd + iva_usd + exento_usd
    gross_total_bs = subtotal_bs + iva_bs + exento_bs
    discount_totals = normalized_discount_totals(
      gross_total_usd: gross_total_usd,
      gross_total_bs: gross_total_bs,
    )
    total_usd = gross_total_usd - discount_totals[:descuento_usd]
    total_bs = gross_total_bs - discount_totals[:descuento_bs]

    {
      subtotal_usd: subtotal_usd,
      subtotal_bs: subtotal_bs,
      exento_usd: exento_usd,
      exento_bs: exento_bs,
      iva_usd: iva_usd,
      iva_bs: iva_bs,
      descuento_usd: discount_totals[:descuento_usd],
      descuento_bs: discount_totals[:descuento_bs],
      total_usd: total_usd,
      total_bs: total_bs,
    }
  end

  private

  def supplier_optional?
    initial_inventory? || intercompany?
  end

  def source_business_differs_from_destination
    return if source_business_id.blank? || business_id.blank?
    return unless source_business_id == business_id

    errors.add(:source_business_id, "debe ser distinto al negocio actual")
  end

  def normalize_invoice_kind
    self.invoice_kind = invoice_kind.presence || INVOICE_KIND_PURCHASE
  end

  def normalize_delivered
    self.delivered = true if delivered.nil?
    self.delivered = true if initial_inventory?
  end

  def normalized_discount_totals(gross_total_usd:, gross_total_bs:)
    priority = supplier&.pricing_currency_priority.presence == 'bs' ? 'bs' : 'usd'
    rate = tasa_dolar.to_d

    discount_usd_input = descuento_usd.to_d
    discount_bs_input = descuento_bs.to_d

    if priority == 'bs'
      discount_bs = [discount_bs_input, 0.to_d].max
      discount_bs = [discount_bs, gross_total_bs].min
      discount_usd = rate.positive? ? (discount_bs / rate) : 0.to_d
    else
      discount_usd = [discount_usd_input, 0.to_d].max
      discount_usd = [discount_usd, gross_total_usd].min
      discount_bs = discount_usd * rate
    end

    self.descuento_usd = discount_usd.round(4)
    self.descuento_bs = discount_bs.round(4)

    {
      descuento_usd: self.descuento_usd.to_d,
      descuento_bs: self.descuento_bs.to_d,
    }
  end

  def prevent_undeliver_when_stock_consumed
    return unless persisted?
    return unless will_save_change_to_delivered?

    previous_value, current_value = delivered_change_to_be_saved
    return unless ActiveModel::Type::Boolean.new.cast(previous_value) && !ActiveModel::Type::Boolean.new.cast(current_value)
    return if initial_inventory?

    any_consumed = purchase_invoice_items.includes(stock_lot: :stock_lot_variations).any? do |item|
      lot = item.stock_lot
      next false if lot.blank?

      lot_level_consumed = lot.quantity_remaining.to_d < lot.quantity_in.to_d
      variation_level_consumed = if lot.stock_lot_variations.any?
        lot.stock_lot_variations.any? do |variation_row|
          variation_row.quantity_remaining.to_d < variation_row.quantity_in.to_d
        end
      else
        false
      end

      lot_level_consumed || variation_level_consumed
    end

    return unless any_consumed

    errors.add(:delivered, "no se puede cambiar a no entregada porque ya se consumió stock de esta factura.")
  end

  def single_initial_inventory_per_business
    return unless initial_inventory?
    return if business_id.blank?

    conflict_scope = self.class.where(business_id: business_id, invoice_kind: INVOICE_KIND_INITIAL_INVENTORY)
    conflict_scope = conflict_scope.where.not(id: id) if persisted?
    return unless conflict_scope.exists?

    errors.add(:base, "Solo puede existir un inventario inicial por negocio.")
  end

  def sync_items_stock_lots_for_delivery_change
    return unless saved_change_to_delivered?

    purchase_invoice_items.find_each do |item|
      item.send(:sync_stock_lot)
    end
  end
end
