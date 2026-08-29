class CashShiftsController < ApplicationController
  CLOSING_VERIFICATION_ACCOUNT_TYPES = %w[biopago pos].freeze
  AUTO_SETTLEMENT_ACCOUNT_TYPES = %w[pos].freeze

  before_action :require_business
  before_action -> { require_module_access!(:cash_shifts) }
  before_action :ensure_can_manage_cash_shifts!, only: %i[create]
  before_action :set_open_cash_shift, only: %i[create]
  before_action :set_cash_shift, only: %i[show close destroy toggle_cashier active_cashier_status]
  before_action :ensure_can_view_cash_shift!, only: %i[show active_cashier_status]
  before_action :ensure_can_close_shift!, only: %i[close]
  before_action :ensure_can_destroy_shift!, only: %i[destroy]
  before_action :ensure_admin_for_cashier_toggle!, only: %i[toggle_cashier]

  def index
    @open_cash_shift = current_business.current_open_cash_shift
    @selected_fecha_desde = parse_filter_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_filter_date(params[:fecha_hasta])

    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    @selected_fecha_desde_value = normalized_filter_date_value(params[:fecha_desde], @selected_fecha_desde)
    @selected_fecha_hasta_value = normalized_filter_date_value(params[:fecha_hasta], @selected_fecha_hasta)
    @filters_applied = [
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip,
    ].any?(&:present?)

    @cash_shifts = current_business.cash_shifts.includes(:opened_by, :closed_by)
    @cash_shifts = @cash_shifts.open unless current_user_admin? || current_user_manager?

    if @selected_fecha_desde.present?
      @cash_shifts = @cash_shifts.where("opened_at >= ?",
                                        @selected_fecha_desde.in_time_zone("America/Caracas").beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      @cash_shifts = @cash_shifts.where("opened_at <= ?",
                                        @selected_fecha_hasta.in_time_zone("America/Caracas").end_of_day)
    end

    @cash_shifts = @cash_shifts.order(opened_at: :desc)

    shift_ids = @cash_shifts.map(&:id)
    @cash_shift_totals_by_id = Hash.new { |hash, key| hash[key] = { usd_total: 0.to_d, ves_total: 0.to_d } }
    return if shift_ids.empty?

    sales = current_business
      .ventas
      .where(cash_shift_id: shift_ids)
      .select(:id, :cash_shift_id, :created_at, :base_currency, :total_usd, :total_bs, :tasa_dolar)
      .to_a

    reference_by_sale_id = SaleCurrencyReferenceService.new(sales).totals_by_sale_id

    sales.each do |sale|
      reference = reference_by_sale_id[sale.id] || {}
      totals = @cash_shift_totals_by_id[sale.cash_shift_id]
      totals[:usd_total] += reference.fetch(:usd_total, sale.total_usd.to_d)
      totals[:ves_total] += reference.fetch(:ves_total, sale.total_bs.to_d)
    end

    @cash_shift_totals_by_id.each_value do |totals|
      totals[:usd_total] = totals[:usd_total].round(2)
      totals[:ves_total] = totals[:ves_total].round(2)
    end
  end

  def create
    if @open_cash_shift.present?
      message = "Ya existe un turno abierto para este negocio."
      return respond_to do |format|
               format.html { redirect_to ventas_path, alert: message }
               format.json do
                 render json: {
                          error: message,
                          redirect_url: ventas_path,
                          cash_shift_url: cash_shift_path(@open_cash_shift),
                        }, status: :unprocessable_entity
               end
             end
    end

    scraper_result = BcvScraperService.call
    unless bcv_scrape_successful?(scraper_result)
      error_message = "No se pudo actualizar correctamente alguna tasa BCV. Intente de nuevo o comuniquese con el administrador."
      return respond_to do |format|
               format.html { redirect_to cash_shifts_path, alert: error_message }
               format.json { render json: { error: error_message }, status: :unprocessable_entity }
             end
    end

    @cash_shift = current_business.cash_shifts.new(
      opening_balance_ves: cash_box_balance_for("VES"),
      opening_balance_usd: cash_box_balance_for("USD"),
      opened_by: Current.user,
      active_cashier: Current.user,
      status: "open",
      opened_at: Time.current,
    )

    if @cash_shift.save
      rates_message = if scraper_result[:status].to_sym == :up_to_date
          "Las tasas ya estan actualizadas."
        else
          "Las tasas han sido actualizadas."
        end

      success_message = "#{rates_message} El turno se abrio correctamente."
      rates_snapshot = open_shift_rates_snapshot

      respond_to do |format|
        format.html { redirect_to ventas_path, notice: success_message }
        format.json do
          render json: {
            success: true,
            message: success_message,
            scraper_status: scraper_result[:status].to_s,
            rates_snapshot: rates_snapshot,
            redirect_url: ventas_path,
            cash_shift_id: @cash_shift.id,
            cash_shift_url: cash_shift_path(@cash_shift),
          }, status: :ok
        end
      end
    else
      error_message = @cash_shift.errors.full_messages.to_sentence.presence || "No se pudo abrir el turno."

      respond_to do |format|
        format.html { redirect_to cash_shifts_path, alert: error_message }
        format.json { render json: { error: error_message }, status: :unprocessable_entity }
      end
    end
  end

  def show
    @close_blocking_drafts_payload = close_blocking_drafts_payload
    load_shift_details
  end

  def close
    blocking_drafts = close_blocking_drafts_payload
    if blocking_drafts.any?
      blocking_message = "Hay borradores pendientes en el panel de cobro. Debes culminarlos o eliminarlos antes de cerrar el turno."
      return respond_to do |format|
               format.html { redirect_to cash_shift_path(@cash_shift), alert: blocking_message }
               format.json do
                 render json: {
                          error: blocking_message,
                          code: "drafts_present",
                          drafts: blocking_drafts,
                        }, status: :unprocessable_entity
               end
             end
    end

    if @cash_shift.closed?
      return respond_to do |format|
               format.html { redirect_to cash_shift_path(@cash_shift), alert: "Este turno ya fue cerrado." }
               format.json { render json: { error: "Este turno ya fue cerrado." }, status: :unprocessable_entity }
             end
    end

    verification_rows = parse_close_verification_rows(close_shift_params[:close_verification_rows])
    expected_rows = build_close_verification_rows(
      build_payments_summary(@cash_shift),
      carryover_by_account_id: cash_box_carryover_for_shift(@cash_shift),
    )

    ensure_close_verification_rows!(verification_rows: verification_rows, expected_rows: expected_rows)
    close_summary = build_close_differences_summary(verification_rows)

    settlement_rows = []
    declared_totals = declared_totals_from_verification_rows(verification_rows)
    close_occurred_at = Time.current

    CashShift.transaction do
      settlement_rows = process_turn_settlements_for_shift!(verification_rows: verification_rows)
      process_cash_withdrawals_for_shift!(verification_rows: verification_rows, occurred_at: close_occurred_at)
      process_payall_recharge_gain_for_shift!(verification_rows: verification_rows, occurred_at: close_occurred_at)

      @cash_shift.close!(
        user: Current.user,
        declared_closing_ves: declared_totals[:ves_total],
        declared_closing_usd: declared_totals[:usd_total],
        notes: build_shift_closing_notes_payload(
          raw_notes: close_shift_params[:closing_notes],
          verification_rows: verification_rows,
          settlement_rows: settlement_rows,
        ),
      )
    end

    notice_message = if close_summary[:has_differences]
        "Turno cerrado con diferencias registradas."
      else
        "Turno cerrado correctamente sin diferencias."
      end

    respond_to do |format|
      format.html { redirect_to cash_shift_path(@cash_shift), notice: notice_message }
      format.json do
        render json: {
          success: true,
          redirect_url: cash_shift_path(@cash_shift),
          message: notice_message,
          close_summary: close_summary,
        }, status: :ok
      end
    end
  rescue ActiveRecord::RecordInvalid
    error_message = @cash_shift.errors.full_messages.to_sentence.presence || "No se pudo cerrar el turno."

    respond_to do |format|
      format.html { redirect_to cash_shift_path(@cash_shift), alert: error_message }
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end

  def destroy
    CashShift.transaction do
      rollback_cash_shift_data!(@cash_shift)
      @cash_shift.destroy!
    end

    redirect_to cash_shifts_path,
                notice: "Turno eliminado correctamente. Se revirtieron ventas, movimientos y saldos asociados."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_to cash_shift_path(@cash_shift),
                alert: e.message.presence || "No se pudo eliminar el turno y revertir los movimientos."
  end

  def toggle_cashier
    unless @cash_shift.open?
      message = "Solo puedes asignar cajero en un turno abierto."
      return respond_to do |format|
               format.html { redirect_back fallback_location: ventas_path, alert: message }
               format.json { render json: { error: message }, status: :unprocessable_entity }
             end
    end

    is_current_user_active_cashier = @cash_shift.active_cashier_id == Current.user&.id
    next_cashier = if is_current_user_active_cashier
        fallback_manager_cashier_for_shift
      else
        Current.user
      end
    @cash_shift.update!(active_cashier: next_cashier)

    notice_message = if is_current_user_active_cashier
        if next_cashier.present?
          "Marcaste salida de caja. Ahora el cajero activo es #{next_cashier.display_name} (#{next_cashier.role_label})."
        else
          "Marcaste salida de caja. No hay encargado activo para asignar como cajero."
        end
      else
        "Marcaste entrada de caja. Quedaste como cajero activo del turno."
      end

    respond_to do |format|
      format.html { redirect_back fallback_location: ventas_path, notice: notice_message }
      format.json do
        render json: {
          success: true,
          message: notice_message,
          cash_shift_id: @cash_shift.id,
          open: @cash_shift.open?,
          active_cashier: active_cashier_payload(@cash_shift),
          can_charge_sale: current_user_can_charge_sale_for_shift?(@cash_shift),
          can_view_all_drafts: current_user_can_view_all_drafts_for_shift?(@cash_shift),
        }, status: :ok
      end
    end
  rescue ActiveRecord::RecordInvalid
    error_message = @cash_shift.errors.full_messages.to_sentence.presence || "No se pudo actualizar el cajero activo."

    respond_to do |format|
      format.html { redirect_back fallback_location: ventas_path, alert: error_message }
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end

  def active_cashier_status
    render json: {
      success: true,
      cash_shift_id: @cash_shift.id,
      open: @cash_shift.open?,
      active_cashier: active_cashier_payload(@cash_shift),
      can_charge_sale: current_user_can_charge_sale_for_shift?(@cash_shift),
      can_view_all_drafts: current_user_can_view_all_drafts_for_shift?(@cash_shift),
      updated_at: @cash_shift.updated_at&.to_i,
    }, status: :ok
  end

  private

  def set_open_cash_shift
    @open_cash_shift = current_business.current_open_cash_shift
  end

  def set_cash_shift
    @cash_shift = current_business.cash_shifts.includes(:opened_by, :closed_by, :active_cashier).find(params[:id])
  end

  def active_cashier_payload(cash_shift)
    cashier = cash_shift&.active_cashier
    return nil if cashier.blank?

    {
      id: cashier.id,
      name: cashier.display_name,
      role_label: cashier.role_label,
      role_key: cashier.role_key,
      female: cashier.female?,
    }
  end

  def current_user_can_charge_sale_for_shift?(cash_shift)
    return true if current_user_admin? || current_user_manager?
    return false unless cash_shift&.open?

    false
  end

  def current_user_can_view_all_drafts_for_shift?(cash_shift)
    return true if current_user_admin? || current_user_manager?
    return false unless cash_shift&.open?

    false
  end

  def ensure_can_view_cash_shift!
    return if current_user_admin? || current_user_manager?
    return if @cash_shift.open?

    redirect_to cash_shifts_path, alert: "Solo encargado o administrador pueden ver turnos cerrados."
  end

  def close_shift_params
    params.require(:cash_shift).permit(
      :declared_closing_ves,
      :declared_closing_usd,
      :closing_notes,
      close_verification_rows: %i[
        account_id
        account_name
        account_type
        currency
        expected_amount
        declared_amount
        withdrawn_amount
        carryover_amount
      ],
    )
  end

  def parse_decimal(raw_value)
    return nil if raw_value.nil?

    string_value = raw_value.to_s.strip
    return nil if string_value.blank?

    normalized = string_value.delete(" ").tr(",", ".")
    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end

  def parse_filter_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr("/", "-"), "%d-%m-%Y") if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def normalized_filter_date_value(raw_value, parsed_value)
    return parsed_value.strftime("%d-%m-%Y") if parsed_value.present?

    raw_value.to_s.strip
  end

  def close_blocking_drafts
    current_business
      .ventas
      .where(status: "draft")
      .includes(:cliente, :user)
      .order(created_at: :asc)
  end

  def close_blocking_drafts_payload
    close_blocking_drafts.map do |draft|
      {
        id: draft.id,
        client_name: draft.cliente_display_name,
        created_by_name: draft.user&.display_name.presence || "Sin personal",
        created_at_label: begin
          draft.created_at.in_time_zone("America/Caracas").strftime("%I:%M %p")
        rescue StandardError
          draft.created_at&.strftime("%I:%M %p")
        end,
      }
    end
  end

  def caracas_date_for(timestamp)
    return nil if timestamp.blank?

    timestamp.in_time_zone("America/Caracas").to_date
  rescue StandardError
    timestamp.to_date
  end

  def ensure_can_close_shift!
    return unless @cash_shift.open?
    return if current_user_admin? || current_user_manager?
    return if @cash_shift.active_cashier_id.present? && @cash_shift.active_cashier_id == Current.user&.id

    active_cashier = @cash_shift.active_cashier
    cashier_name = active_cashier&.display_name.presence || "el cajero activo del turno"
    cashier_role = active_cashier&.role_label.to_s.strip.presence
    role_suffix = cashier_role.present? ? " (#{cashier_role})" : ""

    redirect_to cash_shift_path(@cash_shift), alert: "Este turno solo puede ser cerrado por #{cashier_name}#{role_suffix}."
  end

  def ensure_can_manage_cash_shifts!
    return if can_manage_action?(:manage_cash_shifts)

    deny_access("Solo un encargado o administrador puede abrir y cerrar turnos.")
  end

  def ensure_can_destroy_shift!
    return if current_user_admin?

    deny_access("Solo el administrador puede eliminar turnos.")
  end

  def ensure_admin_for_cashier_toggle!
    return if current_user_admin?

    deny_access("Solo el administrador puede asignar entrada o salida de cajero.")
  end

  def fallback_manager_cashier_for_shift
    User
      .joins(:business_user_assignments)
      .where(business_user_assignments: {
               business_id: current_business.id,
               active: true,
               authorization_level: "manager",
             })
      .where(active: true)
      .order(Arel.sql("LOWER(COALESCE(full_name, username)) ASC"))
      .first
  end

  def rollback_cash_shift_data!(cash_shift)
    return if cash_shift.blank?

    ventas = cash_shift.ventas.includes(:venta_items).to_a

    ventas.each do |venta|
      restore_stock_for_sale!(venta, strict: false)
      delete_account_movements_for_sale!(venta)
      delete_receivable_debts_for_sale!(venta)
      delete_sale_debts_for_sale!(venta)
      venta.destroy!
    end

    delete_shift_closing_movements!(cash_shift)
    delete_shift_settlements!(cash_shift)
    delete_shift_cash_exchanges!(cash_shift)
    recalculate_business_account_balances!
  end

  def delete_shift_closing_movements!(cash_shift)
    pattern = "%[CASH_SHIFT:#{cash_shift.id}]%"

    AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where("account_movements.description LIKE ?", pattern)
      .find_each(&:destroy!)
  end

  def delete_shift_settlements!(cash_shift)
    settlement_ids = settlement_ids_from_shift_notes(cash_shift)
    return if settlement_ids.empty?

    AccountSettlement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where(id: settlement_ids)
      .find_each(&:destroy!)
  end

  def settlement_ids_from_shift_notes(cash_shift)
    payload = parse_shift_notes_payload(cash_shift&.closing_notes)

    Array(payload["auto_settlements"]).filter_map do |row|
      source = row.respond_to?(:to_h) ? row.to_h : {}
      settlement_id = source["settlement_id"] || source[:settlement_id]
      parsed = settlement_id.to_i
      parsed.positive? ? parsed : nil
    end.uniq
  end

  def delete_shift_cash_exchanges!(cash_shift)
    current_business.cambio_efectivos.where(cash_shift_id: cash_shift.id).find_each do |cambio|
      AccountMovement.where(cambio_efectivo_id: cambio.id).find_each(&:destroy!)
      cambio.destroy!
    end
  end

  def recalculate_business_account_balances!
    current_business.accounts.find_each(&:recalculate_balance!)
  end

  def restore_stock_for_sale!(venta, strict: true)
    restored_product_lot_quantities = restore_reserved_product_stock_from_notes!(venta, strict: strict)

    grouped_items = venta.venta_items
                         .select { |item| item.producto_id.present? && item.product_variation_id.present? }
                         .group_by { |item| [item.producto_id, item.product_variation_id] }

    grouped_items.each do |(producto_id, variation_id), items|
      quantity_units = items.sum { |item| item.quantity.to_d }
      quantity_units -= restored_product_lot_quantities.fetch([producto_id.to_i, variation_id.to_i], 0.to_d)
      next unless quantity_units.positive?

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
    end

    restore_reserved_service_stock_from_notes!(venta, strict: strict)
  end

  def restore_reserved_product_stock_from_notes!(venta, strict: true)
    notes_payload = parse_sale_notes_payload(venta.notes)
    rows = Array(notes_payload["product_lot_consumptions"])
    restored_by_key = Hash.new(0.to_d)

    rows.each do |row|
      producto_id = row["product_id"] || row[:product_id]
      variation_id = row["variation_id"] || row[:variation_id]
      stock_lot_id = row["stock_lot_id"] || row[:stock_lot_id]
      quantity_units = parse_decimal(row["quantity"] || row[:quantity]).to_d
      next if producto_id.blank? || variation_id.blank? || !quantity_units.positive?
      next if stock_lot_id.blank?

      restored_exact = restore_product_variation_units_in_lot!(
        producto_id: producto_id,
        variation_id: variation_id,
        stock_lot_id: stock_lot_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
      next unless restored_exact

      restored_by_key[[producto_id.to_i, variation_id.to_i]] += quantity_units
    end

    restored_by_key
  end

  def restore_product_variation_units!(producto_id:, variation_id:, quantity_units:, venta:, strict: true)
    producto = current_business.productos.find_by(id: producto_id)
    return unless producto

    remaining_to_restore = quantity_units.to_d

    producto.stock_lots.ordered_fifo.each do |lot|
      row = lot.variation_row_for(variation_id, create_if_missing: true)
      next unless row

      current_remaining = row.quantity_remaining.to_d
      max_quantity = row.quantity_in.to_d
      available_capacity = max_quantity - current_remaining
      next unless available_capacity.positive?

      restored = [available_capacity, remaining_to_restore].min
      next unless restored.positive?

      row.update!(quantity_remaining: current_remaining + restored)
      lot.sync_quantity_remaining_from_variations!

      remaining_to_restore -= restored
      break if remaining_to_restore <= 0
    end

    return if remaining_to_restore <= 0
    return unless strict

    raise ActiveRecord::RecordInvalid.new(venta),
          "No se pudo restaurar todo el stock de la venta ##{venta.id} (faltan #{remaining_to_restore.to_f.round(4)} unidades)."
  end

  def parse_sale_notes_payload(raw_notes)
    return {} if raw_notes.blank?

    parsed = JSON.parse(raw_notes)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def restore_reserved_service_stock_from_notes!(venta, strict: true)
    notes_payload = parse_sale_notes_payload(venta.notes)
    rows = Array(notes_payload["reserved_service_products"])

    rows.each do |row|
      producto_id = row["product_id"] || row[:product_id]
      variation_id = row["variation_id"] || row[:variation_id]
      stock_lot_id = row["stock_lot_id"] || row[:stock_lot_id]
      quantity_units = parse_decimal(row["quantity"] || row[:quantity]).to_d
      next if producto_id.blank? || variation_id.blank? || !quantity_units.positive?

      if stock_lot_id.present?
        restored_exact = restore_product_variation_units_in_lot!(
          producto_id: producto_id,
          variation_id: variation_id,
          stock_lot_id: stock_lot_id,
          quantity_units: quantity_units,
          venta: venta,
          strict: strict,
        )
        next if restored_exact
      end

      restore_product_variation_units!(
        producto_id: producto_id,
        variation_id: variation_id,
        quantity_units: quantity_units,
        venta: venta,
        strict: strict,
      )
    end
  end

  def restore_product_variation_units_in_lot!(producto_id:, variation_id:, stock_lot_id:, quantity_units:, venta:, strict: true)
    producto = current_business.productos.find_by(id: producto_id)
    if producto.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro el producto ##{producto_id} para restaurar stock de la venta ##{venta.id}."
    end

    lot = producto.stock_lots.find_by(id: stock_lot_id)
    if lot.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro el lote ##{stock_lot_id} para restaurar stock de la venta ##{venta.id}."
    end

    row = lot.variation_row_for(variation_id, create_if_missing: true)
    if row.blank?
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se encontro la variacion para restaurar en el lote ##{lot.id} de la venta ##{venta.id}."
    end

    current_remaining = row.quantity_remaining.to_d
    max_quantity = row.quantity_in.to_d
    available_capacity = max_quantity - current_remaining

    if quantity_units.to_d > available_capacity
      return false unless strict

      raise ActiveRecord::RecordInvalid.new(venta),
            "No se pudo restaurar en el lote ##{lot.id} toda la cantidad de la venta ##{venta.id}."
    end

    row.update!(quantity_remaining: current_remaining + quantity_units.to_d)
    lot.sync_quantity_remaining_from_variations!
    true
  end

  def delete_account_movements_for_sale!(venta)
    pattern = "%[VENTA:#{venta.id}]%"

    AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where("account_movements.description LIKE ?", pattern)
      .find_each(&:destroy!)
  end

  def delete_receivable_debts_for_sale!(venta)
    receivable_scope = current_business.debts.where(debt_kind: "receivable")

    receivable_scope
      .where(venta_id: venta.id)
      .find_each(&:destroy!)

    sale_pattern = "%[VENTA:#{venta.id}]%"
    receivable_scope
      .where("description LIKE ?", sale_pattern)
      .find_each(&:destroy!)

    legacy_name_pattern = "Saldo venta ##{venta.id}%"
    receivable_scope
      .where("name LIKE ?", legacy_name_pattern)
      .find_each(&:destroy!)
  end

  def delete_sale_debts_for_sale!(venta)
    current_business
      .debts
      .where(venta_id: venta.id)
      .find_each(&:destroy!)

    pattern = "%[VENTA:#{venta.id}]%"
    current_business
      .debts
      .where("description LIKE ?", pattern)
      .find_each(&:destroy!)
  end

  def load_shift_details
    @sales = @cash_shift.ventas.includes(:cliente, :user, :venta_payments).order(created_at: :asc)
    reference_service = SaleCurrencyReferenceService.new(@sales)
    @sales_reference_by_id = reference_service.totals_by_sale_id
    @sales_reference_rates_by_date = reference_service.rates_by_date

    @sales_count = @sales.size
    @sales_total_usd = @sales_reference_by_id.values.sum { |row| row[:usd_total].to_d }.round(2)
    @sales_total_ves = @sales_reference_by_id.values.sum { |row| row[:ves_total].to_d }.round(2)

    @payments_summary = build_payments_summary(@cash_shift)
    @payments_in_total = @payments_summary.sum { |row| row[:incoming] }
    @payments_out_total = @payments_summary.sum { |row| row[:outgoing] }
    @payments_net_total = @payments_summary.sum { |row| row[:net] }
    @cash_box_carryover_by_account_id = cash_box_carryover_for_shift(@cash_shift)
    @close_verification_rows = build_close_verification_rows(
      @payments_summary,
      carryover_by_account_id: @cash_box_carryover_by_account_id,
    )
    @closing_verification_report_rows = close_summary_rows_from_notes(@cash_shift)
    @closing_notes_text = closing_notes_text_from_notes(@cash_shift)

    grouped_sales = @sales.group_by(&:user)
    @seller_summary = grouped_sales.map do |user, sales|
      {
        user_name: user&.display_name.presence || "Sin usuario",
        sales_count: sales.size,
        total_usd: sales.sum { |sale| @sales_reference_by_id.dig(sale.id, :usd_total).to_d }.round(2),
        total_ves: sales.sum { |sale| @sales_reference_by_id.dig(sale.id, :ves_total).to_d }.round(2),
      }
    end.sort_by { |row| row[:user_name].to_s.downcase }

    @sales_count_by_rate_date = @sales.each_with_object(Hash.new(0)) do |sale, hash|
      rate_date = @sales_reference_by_id.dig(sale.id, :rate_date) || caracas_date_for(sale.created_at)
      hash[rate_date] += 1 if rate_date.present?
    end

    shift_rate_dates = @sales_count_by_rate_date.keys
    opened_date = caracas_date_for(@cash_shift.opened_at)
    closed_date = caracas_date_for(@cash_shift.closed_at)
    shift_rate_dates << opened_date if opened_date.present?
    shift_rate_dates << closed_date if closed_date.present?

    @shift_exchange_rates_by_date = SaleCurrencyReferenceService.exchange_rates_for_dates(shift_rate_dates)

    @shift_exchange_rate_rows = shift_rate_dates.compact.uniq.sort.reverse.map do |date|
      day_rates = @shift_exchange_rates_by_date.fetch(date, { usd_rate: 0.to_d, eur_rate: 0.to_d })
      {
        date: date,
        usd_rate: day_rates[:usd_rate].to_d.round(4),
        eur_rate: day_rates[:eur_rate].to_d.round(4),
        sales_count: @sales_count_by_rate_date[date].to_i,
      }
    end
  end

  def build_payments_summary(cash_shift)
    grouped_rows = shift_movements_scope(cash_shift)
      .includes(:account)
      .group_by(&:account_id)

    grouped_rows.map do |(account_id, movements)|
      account = movements.first&.account || current_business.accounts.find_by(id: account_id)
      currency = account&.currency.to_s.upcase
      incoming = movements.select { |movement| movement.movement_kind == "income" }
        .sum { |movement| movement.amount.to_d }
      outgoing = movements.select { |movement| movement.movement_kind == "expense" }
        .sum { |movement| movement.amount.to_d }

      {
        account_id: account_id,
        account_name: account&.name.to_s.presence || "Cuenta eliminada",
        account_type: account&.account_type.to_s.presence || "unknown",
        currency: currency,
        currency_symbol: Account::CURRENCIES.dig(currency.to_s.upcase, :symbol) || currency.to_s,
        incoming: incoming,
        outgoing: outgoing,
        net: incoming - outgoing,
      }
    end.sort_by { |row| [row[:account_name].to_s.downcase, row[:currency].to_s] }
  end

  def build_close_verification_rows(payments_summary, carryover_by_account_id: {})
    carryover_map = Hash(carryover_by_account_id).transform_keys(&:to_i)

    rows = Array(payments_summary).filter_map do |row|
      account_id = row[:account_id]
      account_type = row[:account_type].to_s
      carryover_amount = carryover_map.fetch(account_id.to_i, 0.to_d).to_d
      expected_amount = row[:net].to_d + carryover_amount

      next if account_id.blank?
      next unless CLOSING_VERIFICATION_ACCOUNT_TYPES.include?(account_type)
      next unless expected_amount.positive?

      {
        account_id: account_id.to_i,
        account_name: row[:account_name].to_s,
        account_type: account_type,
        currency: row[:currency].to_s.upcase,
        currency_symbol: row[:currency_symbol].to_s,
        expected_amount: expected_amount.round(2),
        carryover_from_previous: carryover_amount.round(2),
      }
    end

    listed_account_ids = rows.map { |row| row[:account_id].to_i }

    cash_box_accounts.each do |account|
      next unless account.cash_box_role?

      expected_amount = account.balance.to_d.round(2)
      next unless expected_amount.positive?

      rows << {
        account_id: account.id,
        account_name: account.name.to_s,
        account_type: account.account_type,
        currency: account.currency.to_s.upcase,
        currency_symbol: account.currency_symbol,
        expected_amount: expected_amount,
        carryover_from_previous: 0.to_d,
      }
    end

    payall = payall_account
    if payall.present?
      expected_amount = payall.balance.to_d.round(2)
      rows << {
        account_id: payall.id,
        account_name: payall.name.to_s,
        account_type: payall.account_type,
        currency: payall.currency.to_s.upcase,
        currency_symbol: payall.currency_symbol,
        expected_amount: expected_amount,
        carryover_from_previous: 0.to_d,
      }
    end

    pending_biopago_totals_by_account_id.each do |account_id, pending_total|
      normalized_pending_total = pending_total.to_d.round(2)
      next unless normalized_pending_total.positive?

      account = current_business.accounts.find_by(id: account_id)
      next if account.blank?

      existing_row = rows.find { |row| row[:account_id].to_i == account_id }
      if existing_row.present?
        existing_row[:expected_amount] = normalized_pending_total
        existing_row[:currency] = account.currency.to_s.upcase
        existing_row[:currency_symbol] = account.currency_symbol
      else
        rows << {
          account_id: account.id,
          account_name: account.name.to_s,
          account_type: account.account_type,
          currency: account.currency.to_s.upcase,
          currency_symbol: account.currency_symbol,
          expected_amount: normalized_pending_total,
          carryover_from_previous: 0.to_d,
        }
      end

      listed_account_ids << account_id unless listed_account_ids.include?(account_id)
    end

    account_type_order = {
      "biopago" => 0,
      "pos" => 1,
      "cash_box" => 2,
    }

    rows.sort_by do |row|
      [account_type_order.fetch(row[:account_type], 99), row[:account_name].downcase, row[:account_id]]
    end
  end

  def pending_biopago_totals_by_account_id
    current_business.accounts.where(account_type: "biopago").each_with_object({}) do |account, hash|
      pending_total = account.account_movements.where(account_settlement_id: nil).sum(
        Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
      ).to_d

      hash[account.id] = pending_total if pending_total.positive?
    end
  end

  def parse_close_verification_rows(raw_rows)
    Array(raw_rows).filter_map do |raw_row|
      row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
      account_id = row["account_id"] || row[:account_id]
      next if account_id.blank?

      {
        account_id: account_id.to_i,
        account_name: (row["account_name"] || row[:account_name]).to_s,
        account_type: (row["account_type"] || row[:account_type]).to_s,
        currency: (row["currency"] || row[:currency]).to_s.upcase,
        expected_amount: parse_decimal(row["expected_amount"] || row[:expected_amount]).to_d,
        declared_amount: parse_decimal(row["declared_amount"] || row[:declared_amount]),
        withdrawn_amount: parse_decimal(row["withdrawn_amount"] || row[:withdrawn_amount]),
        carryover_amount: parse_decimal(row["carryover_amount"] || row[:carryover_amount]),
      }
    end
  end

  def ensure_close_verification_rows!(verification_rows:, expected_rows:)
    expected_by_account_id = Array(expected_rows).index_by { |row| row[:account_id].to_i }
    provided_by_account_id = Array(verification_rows).index_by { |row| row[:account_id].to_i }
    payall_id = payall_account&.id

    expected_by_account_id.each do |account_id, expected_row|
      provided_row = provided_by_account_id[account_id]
      if provided_row.blank?
        @cash_shift.errors.add(:base, "Falta registrar el monto total de #{expected_row[:account_name]}.")
        next
      end

      declared_amount = provided_row[:declared_amount]
      if declared_amount.nil?
        @cash_shift.errors.add(:base, "El monto total de #{expected_row[:account_name]} es obligatorio.")
        next
      end

      if declared_amount.to_d.negative?
        @cash_shift.errors.add(:base, "El monto total de #{expected_row[:account_name]} no puede ser negativo.")
      end

      if payall_id.present? && account_id == payall_id && declared_amount.to_d < expected_row[:expected_amount].to_d
        @cash_shift.errors.add(:base,
                               "El saldo real de Payall debe ser mayor o igual al saldo mostrado en el sistema.")
      end

      if expected_row[:account_type].to_s == "cash_box"
        withdrawn_amount = provided_row[:withdrawn_amount]

        if withdrawn_amount.nil?
          @cash_shift.errors.add(:base, "El retiro de efectivo de #{expected_row[:account_name]} es obligatorio.")
          next
        end

        if withdrawn_amount.to_d.negative?
          @cash_shift.errors.add(:base,
                                 "El retiro de efectivo de #{expected_row[:account_name]} no puede ser negativo.")
          next
        end

        if withdrawn_amount.to_d > declared_amount.to_d
          @cash_shift.errors.add(:base,
                                 "El retiro de efectivo de #{expected_row[:account_name]} no puede exceder el monto declarado.")
          next
        end

        provided_row[:carryover_amount] = (declared_amount.to_d - withdrawn_amount.to_d).round(2)
      else
        provided_row[:withdrawn_amount] = 0.to_d
        provided_row[:carryover_amount] = 0.to_d
      end
    end

    raise ActiveRecord::RecordInvalid, @cash_shift if @cash_shift.errors.any?
  end

  def declared_totals_from_verification_rows(verification_rows)
    totals = {
      ves_total: 0.to_d,
      usd_total: 0.to_d,
    }

    Array(verification_rows).each do |row|
      amount = row[:declared_amount].to_d
      currency = row[:currency].to_s.upcase

      if currency == "VES"
        totals[:ves_total] += amount
      elsif %w[USD USDT].include?(currency)
        totals[:usd_total] += amount
      end
    end

    {
      ves_total: totals[:ves_total].round(2),
      usd_total: totals[:usd_total].round(2),
    }
  end

  def process_turn_settlements_for_shift!(verification_rows:)
    settlement_rows = []

    current_business.accounts.where(account_type: AUTO_SETTLEMENT_ACCOUNT_TYPES).find_each do |account|
      pending_scope = pending_shift_movements_scope(account: account, cash_shift: @cash_shift)
      pending_total = pending_scope.sum(
        Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
      ).to_d
      next unless pending_total.positive?

      settlement_account = account.settlement_account

      pending_count = pending_scope.count
      period_start = pending_scope.minimum(:occurred_at)
      period_end = pending_scope.maximum(:occurred_at)

      settlement = account.account_settlements.create!(
        total_amount: pending_total,
        movements_count: pending_count,
        closed_at: Time.current,
        period_start_at: period_start,
        period_end_at: period_end,
        settlement_account: settlement_account,
      )

      pending_scope.update_all(account_settlement_id: settlement.id, updated_at: Time.current)
      account.recalculate_balance!

      settlement_rows << {
        account_id: account.id,
        account_name: account.name,
        account_type: account.account_type,
        settlement_id: settlement.id,
        expected_amount: pending_total.round(2),
        declared_amount: pending_total.round(2),
        commission_amount: 0.to_d,
        processed: false,
      }
    end

    settlement_rows
  end

  def pending_shift_movements_scope(account:, cash_shift:)
    account
      .account_movements
      .where(account_settlement_id: nil)
      .where(movement_kind: "income")
      .where(occurred_at: shift_time_range_for(cash_shift))
  end

  def shift_movements_scope(cash_shift)
    AccountMovement
      .joins(:account)
      .where(accounts: { business_id: current_business.id })
      .where(occurred_at: shift_time_range_for(cash_shift))
  end

  def shift_time_range_for(cash_shift)
    start_at = cash_shift.opened_at
    end_at = cash_shift.closed_at || Time.current
    start_at..end_at
  end

  def build_shift_closing_notes_payload(raw_notes:, verification_rows:, settlement_rows:)
    payload = {
      notes: raw_notes.to_s.strip.presence,
      close_verification_rows: Array(verification_rows).map do |row|
        {
          account_id: row[:account_id],
          account_name: row[:account_name],
          account_type: row[:account_type],
          currency: row[:currency],
          expected_amount: row[:expected_amount].to_d.round(2).to_s("F"),
          declared_amount: row[:declared_amount].to_d.round(2).to_s("F"),
          withdrawn_amount: row[:withdrawn_amount].to_d.round(2).to_s("F"),
          carryover_amount: row[:carryover_amount].to_d.round(2).to_s("F"),
        }
      end,
      auto_settlements: Array(settlement_rows).map do |row|
        {
          account_id: row[:account_id],
          account_name: row[:account_name],
          account_type: row[:account_type],
          settlement_id: row[:settlement_id],
          expected_amount: row[:expected_amount].to_d.round(2).to_s("F"),
          declared_amount: row[:declared_amount].to_d.round(2).to_s("F"),
          commission_amount: row[:commission_amount].to_d.round(2).to_s("F"),
          processed: ActiveModel::Type::Boolean.new.cast(row[:processed]),
        }
      end,
    }

    compact_payload = payload.compact
    compact_payload.to_json
  end

  def parse_shift_notes_payload(raw_notes)
    return {} if raw_notes.blank?

    parsed = JSON.parse(raw_notes)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def cash_box_carryover_for_shift(cash_shift)
    return {} if cash_shift.blank?

    {}
  end

  def cash_box_accounts
    current_business.accounts.where(account_type: "cash_box")
  end

  def payall_account
    current_business.accounts.find do |account|
      account.name.to_s.strip.downcase.include?("payall")
    end
  end

  def cash_box_balance_for(currency)
    cash_box_accounts
      .where(cash_role: "cash_box", currency: currency.to_s.upcase)
      .sum(:balance)
      .to_d
      .round(2)
  end

  def process_cash_withdrawals_for_shift!(verification_rows:, occurred_at: nil)
    cash_rows = Array(verification_rows).select { |row| row[:account_type].to_s == "cash_box" }
    cash_rows.each do |row|
      withdrawn = row[:withdrawn_amount].to_d
      next unless withdrawn.positive?

      source_account = current_business.accounts.find_by(id: row[:account_id])
      next if source_account.blank?

      if source_account.cash_role != "cash_box"
        @cash_shift.errors.add(:base, "La cuenta #{source_account.name} no es una caja operativa.")
        raise ActiveRecord::RecordInvalid, @cash_shift
      end

      destination_account = current_business.accounts.find_by(
        account_type: "cash_box",
        cash_role: "cash_deposit",
        currency: source_account.currency,
      )

      if destination_account.blank?
        @cash_shift.errors.add(:base,
                               "No existe la cuenta deposito en #{source_account.currency} para registrar el retiro.")
        raise ActiveRecord::RecordInvalid, @cash_shift
      end

      movement_occurred_at = occurred_at || Time.current
      source_account.account_movements.create!(
        movement_kind: "expense",
        amount: withdrawn,
        description: "Retiro de caja por cierre de turno ##{@cash_shift.id} [CASH_SHIFT:#{@cash_shift.id}]",
        occurred_at: movement_occurred_at,
      )

      destination_account.account_movements.create!(
        movement_kind: "income",
        amount: withdrawn,
        description: "Deposito desde caja por cierre de turno ##{@cash_shift.id} [CASH_SHIFT:#{@cash_shift.id}]",
        occurred_at: movement_occurred_at,
      )
    end
  end

  def process_payall_recharge_gain_for_shift!(verification_rows:, occurred_at: nil)
    payall = payall_account
    return if payall.blank?

    payall_row = Array(verification_rows).find { |row| row[:account_id].to_i == payall.id }
    return if payall_row.blank?

    reported_amount = payall_row[:declared_amount].to_d
    current_balance = payall.balance.to_d
    gain_amount = (reported_amount - current_balance).round(2)
    return unless gain_amount.positive?

    payall.account_movements.create!(
      movement_kind: "income",
      amount: gain_amount,
      description: "Ganancia de Recargas",
      occurred_at: occurred_at || Time.current,
    )
  end

  def close_summary_rows_from_notes(cash_shift)
    notes_payload = parse_shift_notes_payload(cash_shift&.closing_notes)
    rows = Array(notes_payload["close_verification_rows"])

    rows.filter_map do |raw_row|
      row = raw_row.respond_to?(:to_h) ? raw_row.to_h : {}
      expected_amount = parse_decimal(row["expected_amount"] || row[:expected_amount]).to_d.round(2)
      declared_amount = parse_decimal(row["declared_amount"] || row[:declared_amount]).to_d.round(2)
      withdrawn_amount = parse_decimal(row["withdrawn_amount"] || row[:withdrawn_amount]).to_d.round(2)
      carryover_amount = parse_decimal(row["carryover_amount"] || row[:carryover_amount]).to_d.round(2)

      difference_amount = (declared_amount - expected_amount).round(2)
      difference_kind = if difference_amount.zero?
          "match"
        elsif difference_amount.positive?
          "surplus"
        else
          "shortage"
        end

      currency = (row["currency"] || row[:currency]).to_s.upcase
      currency_symbol = Account::CURRENCIES.dig(currency, :symbol) || currency

      {
        account_id: (row["account_id"] || row[:account_id]).to_i,
        account_name: (row["account_name"] || row[:account_name]).to_s,
        account_type: (row["account_type"] || row[:account_type]).to_s,
        currency: currency,
        currency_symbol: currency_symbol,
        expected_amount: expected_amount,
        declared_amount: declared_amount,
        difference_amount: difference_amount,
        difference_kind: difference_kind,
        withdrawn_amount: withdrawn_amount,
        carryover_amount: carryover_amount,
      }
    end
  end

  def closing_notes_text_from_notes(cash_shift)
    notes_payload = parse_shift_notes_payload(cash_shift&.closing_notes)
    notes_payload["notes"].to_s.strip.presence
  end

  def build_close_differences_summary(verification_rows)
    rows = Array(verification_rows).map do |row|
      expected_amount = row[:expected_amount].to_d.round(2)
      declared_amount = row[:declared_amount].to_d.round(2)
      difference_amount = (declared_amount - expected_amount).round(2)

      {
        account_id: row[:account_id].to_i,
        account_name: row[:account_name].to_s,
        account_type: row[:account_type].to_s,
        currency: row[:currency].to_s.upcase,
        expected_amount: expected_amount.to_s("F"),
        declared_amount: declared_amount.to_s("F"),
        difference_amount: difference_amount.to_s("F"),
        withdrawn_amount: row[:withdrawn_amount].to_d.round(2).to_s("F"),
        carryover_amount: row[:carryover_amount].to_d.round(2).to_s("F"),
      }
    end

    {
      has_differences: rows.any? { |row| row[:difference_amount].to_d.nonzero? },
      rows: rows,
    }
  end

  def open_shift_rates_snapshot
    bcv_descriptions = ["Dolar BCV", "Euro BCV"]

    bcv_rates = bcv_descriptions.filter_map do |description|
      rate = TasaCambio.latest_for(description)
      formatted_rate_snapshot(rate)
    end

    other_rates = TasaCambio.latest_by_description(excluding: bcv_descriptions).map do |rate|
      formatted_rate_snapshot(rate)
    end

    {
      bcv_rates: bcv_rates,
      other_rates: other_rates,
    }
  end

  def formatted_rate_snapshot(rate)
    return nil if rate.blank?

    {
      description: rate.description.to_s,
      value: rate.valor.to_d.to_f,
      symbol: rate.symbol.to_s,
      fecha_referencia: rate.fecha_referencia,
      updated_at: rate.updated_at&.in_time_zone("America/Caracas")&.iso8601,
    }
  end

  def bcv_scrape_successful?(scraper_result)
    return false unless scraper_result.is_a?(Hash)

    status = scraper_result[:status].to_s
    return false unless %w[updated up_to_date].include?(status)

    reference_date = scraper_result[:fecha_referencia]
    latest_dolar = TasaCambio.where(description: "Dolar BCV").maximum(:fecha_referencia)
    latest_euro = TasaCambio.where(description: "Euro BCV").maximum(:fecha_referencia)

    return false if latest_dolar.blank? || latest_euro.blank?
    return true if reference_date.blank?

    latest_dolar >= reference_date && latest_euro >= reference_date
  end
end
