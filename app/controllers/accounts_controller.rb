class AccountsController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:accounts) }
  before_action :set_account, only: %i[show edit update destroy set_primary unset_primary transfer register_payment
                                       edit_movement update_movement destroy_movement]
  before_action :set_manual_movement, only: %i[edit_movement update_movement]
  before_action :set_movement_for_destroy, only: %i[destroy_movement]
  before_action :set_bcv_rate, only: %i[index show]
  before_action :load_bank_accounts_ves, only: %i[new edit create update]
  before_action :load_transfer_support_data, only: %i[index]
  before_action :ensure_accounts_management_allowed!, only: %i[new create edit update destroy set_primary unset_primary
                                                               transfer register_payment edit_movement update_movement
                                                               destroy_movement]

  def index
    @accounts = accounts_visible_scope.with_attached_logo.order(name: :asc)
    totals = accounts_visible_scope.group(:currency).sum(:balance)
    @currency_totals = Account::CURRENCIES.keys.index_with { |code| totals[code] || 0 }
  end

  def show
    @highlight_movement_id = params[:movement_id].to_i if params[:movement_id].to_i.positive?
    initialize_movement_filters

    if @account.settlement_enabled? && current_user_admin?
      pending_scope = apply_movement_date_filters(@account.account_movements.where(account_settlement_id: nil))
      @pending_movements_count = pending_scope.count
      @pending_movements_total = pending_scope.sum(
        Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
      ).to_d
      @pending_period_start = pending_scope.minimum(:occurred_at)
      @pending_period_end = pending_scope.maximum(:occurred_at)
      @account_settlements = @account.account_settlements.where(processed_at: nil)
      @account_settlements = if @account.account_type == "biopago"
          @account_settlements.order(period_start_at: :asc, closed_at: :asc)
        else
          @account_settlements.order(closed_at: :desc)
        end
      @processed_settlements_count = @account.account_settlements.where.not(processed_at: nil).count

      if @account.account_type == "biopago"
        biopago_close_info = build_biopago_pending_close_info(@account)
        @biopago_pending_day_to_close = biopago_close_info[:day]
        @biopago_pending_day_total = biopago_close_info[:total]
        @biopago_pending_day_movements_count = biopago_close_info[:movements_count]
        @biopago_can_close_pending_day = biopago_close_info[:closable]
      end

      ordered_scope = pending_scope.order(occurred_at: :desc, id: :desc)
      @pagy, @account_movements = pagy(ordered_scope, items: 24)
      @movement_query_params = build_movement_query_params
      return
    end

    ordered_scope = apply_movement_date_filters(@account.account_movements).order(occurred_at: :desc, id: :desc)
    @pagy, @account_movements = pagy(ordered_scope, items: 24)
    @movement_query_params = build_movement_query_params
  end

  def new
    @account = current_business.accounts.new(account_type: "bank_account", currency: "USD", theme_color: "sky",
                                             balance: 0, active: true)
  end

  def create
    @account = current_business.accounts.new(account_params)

    if @account.save
      Account.sync_shared_fields!(@account)
      redirect_to accounts_path, notice: "Cuenta creada"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      Account.sync_shared_fields!(@account)
      redirect_to account_path(@account), notice: "Cuenta actualizada"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    shared_key = @account.shared_key
    accounts_to_delete = if shared_key.present? && @account.syncable_across_businesses?
        Account.where(shared_key: shared_key)
      else
        Account.where(id: @account.id)
      end

    account_ids = accounts_to_delete.select(:id)
    Account.where(settlement_account_id: account_ids)
           .update_all(settlement_account_id: nil, updated_at: Time.current)
    AccountSettlement.where(settlement_account_id: account_ids)
                     .update_all(settlement_account_id: nil, updated_at: Time.current)

    accounts_to_delete.find_each(&:destroy)
    redirect_to accounts_path, notice: "Cuenta eliminada"
  end

  def set_primary
    unless @account.account_type == "bank_account"
      redirect_to accounts_path, alert: "Solo cuentas bancarias pueden ser principales."
      return
    end

    if @account.update(is_primary: true)
      redirect_to accounts_path, notice: "Cuenta principal actualizada."
    else
      redirect_to accounts_path, alert: @account.errors.full_messages.to_sentence
    end
  end

  def unset_primary
    unless @account.account_type == "bank_account"
      redirect_to accounts_path, alert: "Solo cuentas bancarias pueden ser principales."
      return
    end

    if @account.update(is_primary: false)
      redirect_to accounts_path, notice: "Cuenta principal removida."
    else
      redirect_to accounts_path, alert: @account.errors.full_messages.to_sentence
    end
  end

  def transfer
    target_account = current_business.accounts.find_by(id: params[:target_account_id])
    return redirect_to accounts_path, alert: "Selecciona una cuenta destino valida." if target_account.blank?

    if target_account.id == @account.id
      return redirect_to accounts_path, alert: "La cuenta destino debe ser diferente a la cuenta origen."
    end

    transfer_date = parse_transfer_date(params[:transfer_date])
    return redirect_to accounts_path, alert: "Indica una fecha valida para la transferencia." if transfer_date.blank?

    amount_from = parse_transfer_decimal(params[:amount_from])
    return redirect_to accounts_path, alert: "Indica un monto origen valido mayor a 0." unless amount_from.positive?

    transfer_payment_method = normalize_transfer_payment_method(params[:transfer_payment_method])
    if transfer_payment_method.blank?
      return redirect_to accounts_path,
                         alert: "Selecciona un metodo de pago valido para la transferencia."
    end

    reference = params[:reference].to_s.strip
    unless valid_bank_reference?(reference)
      return redirect_to accounts_path,
                         alert: "La referencia debe tener exactamente 4 digitos."
    end

    suggested_target = suggested_transfer_amount(
      amount_from: amount_from,
      from_account: @account,
      to_account: target_account,
      transfer_date: transfer_date,
    )
    if suggested_target.blank?
      return redirect_to accounts_path,
                         alert: "No se pudo convertir el monto para la cuenta destino."
    end

    amount_to = parse_transfer_decimal(params[:amount_to])
    amount_to = suggested_target if amount_to <= 0
    return redirect_to accounts_path, alert: "Indica un monto destino valido mayor a 0." unless amount_to.positive?

    commission_amount = 0.to_d
    commission_account = nil

    if transfer_commission_applicable?(transfer_payment_method)
      commission_account = current_business.accounts.find_by(id: params[:commission_account_id])
      if commission_account.blank? || ![target_account.id, @account.id].include?(commission_account.id)
        return redirect_to accounts_path,
                           alert: "Selecciona cual cuenta asumira la comision de la transferencia."
      end

      commission_amount = parse_transfer_decimal(params[:commission_amount])
      unless commission_amount.positive?
        commission_amount = suggested_transfer_commission_amount(
          amount_from: amount_from,
          from_account: @account,
          commission_account: commission_account,
          transfer_date: transfer_date,
        )
      end

      unless commission_amount&.positive?
        return redirect_to accounts_path,
                           alert: "No se pudo calcular la comision de la transferencia."
      end
    end

    source_required = amount_from + (commission_account&.id == @account.id ? commission_amount : 0.to_d)
    if source_required > @account.balance.to_d
      return redirect_to accounts_path,
                         alert: @account.insufficient_balance_message(source_required)
    end

    if commission_account&.id == target_account.id
      target_available_after_transfer = target_account.balance.to_d + amount_to.to_d
      if commission_amount > target_available_after_transfer
        return redirect_to accounts_path,
                           alert: target_account.insufficient_balance_message(
                             commission_amount,
                             available_balance: target_available_after_transfer,
                           )
      end
    end

    caracas_now = Time.current.in_time_zone("America/Caracas")
    occurred_at = caracas_now.change(year: transfer_date.year, month: transfer_date.month, day: transfer_date.day)

    AccountMovement.transaction do
      outgoing = @account.account_movements.create!(
        movement_kind: "expense",
        amount: amount_from,
        occurred_at: occurred_at,
        payment_method: transfer_payment_method_for(@account, transfer_payment_method),
        reference: reference.presence,
        description: transfer_movement_description(base: "Transferencia a cuenta #{target_account.name} [ACCOUNT:#{target_account.id}]", reference: reference),
      )

      incoming = target_account.account_movements.create!(
        movement_kind: "income",
        amount: amount_to,
        occurred_at: occurred_at,
        payment_method: transfer_payment_method_for(target_account, transfer_payment_method),
        reference: reference.presence,
        description: transfer_movement_description(base: "Transferencia desde cuenta #{@account.name} [ACCOUNT:#{@account.id}] [AM:#{outgoing.id}]", reference: reference),
      )

      outgoing.update!(
        description: transfer_movement_description(base: "Transferencia a cuenta #{target_account.name} [ACCOUNT:#{target_account.id}] [AM:#{incoming.id}]", reference: reference),
      )

      if commission_amount.positive? && commission_account.present?
        commission_account.account_movements.create!(
          movement_kind: "expense",
          amount: commission_amount,
          occurred_at: occurred_at,
          payment_method: transfer_payment_method_for(commission_account, transfer_payment_method),
          reference: reference.presence,
          description: transfer_movement_description(base: "Comision de #{transfer_payment_method_label(transfer_payment_method)} por transferencia a cuenta #{target_account.name} [ACCOUNT:#{target_account.id}] [AM:#{incoming.id}]", reference: reference),
        )
      end
    end

    redirect_to accounts_path, notice: "Transferencia registrada correctamente."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to accounts_path, alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def register_payment
    if Account::SPECIAL_ACCOUNT_TYPES.include?(@account.account_type)
      return redirect_to account_path(@account), alert: "No se pueden registrar pagos en cuentas especiales."
    end

    concept = params[:concept].to_s.strip
    return redirect_to account_path(@account), alert: "Indica el concepto del pago." if concept.blank?

    payment_date = parse_transfer_date(params[:payment_date])
    return redirect_to account_path(@account), alert: "Indica una fecha valida para el pago." if payment_date.blank?

    amount = parse_transfer_decimal(params[:amount])
    return redirect_to account_path(@account), alert: "Indica un monto valido mayor a 0." unless amount.positive?

    movement_kind = normalize_payment_movement_kind(params[:movement_kind])
    if movement_kind.blank?
      return redirect_to account_path(@account),
                         alert: "Selecciona un tipo de movimiento valido (debito o credito)."
    end

    include_commission = ActiveModel::Type::Boolean.new.cast(params[:include_commission])
    include_commission = false unless movement_kind == "expense"
    commission_amount = include_commission ? parse_transfer_decimal(params[:commission_amount]) : 0.to_d
    if include_commission && !commission_amount.positive?
      return redirect_to account_path(@account), alert: "Indica un monto de comision valido mayor a 0."
    end

    total_debit = movement_kind == "expense" ? (amount + commission_amount).round(2) : 0.to_d

    if movement_kind == "expense" && total_debit > @account.balance.to_d
      return redirect_to account_path(@account), alert: @account.insufficient_balance_message(total_debit)
    end

    caracas_now = Time.current.in_time_zone("America/Caracas")
    occurred_at = caracas_now.change(year: payment_date.year, month: payment_date.month, day: payment_date.day)

    payment_method = @account.account_type == "bank_account" ? "transfer" : nil
    reference = params[:reference].to_s.strip

    if @account.account_type == "bank_account" && !valid_bank_reference?(reference)
      return redirect_to account_path(@account), alert: "La referencia debe tener exactamente 4 digitos."
    end

    movement = nil

    AccountMovement.transaction do
      movement = @account.account_movements.create!(
        movement_kind: movement_kind,
        amount: amount,
        occurred_at: occurred_at,
        payment_method: payment_method,
        reference: reference.presence,
        description: transfer_movement_description(
          base: "#{movement_kind == 'expense' ? 'Pago' : 'Credito manual'}: #{concept}",
          reference: reference,
        ),
      )

      if include_commission && commission_amount.positive?
        @account.account_movements.create!(
          movement_kind: "expense",
          amount: commission_amount,
          occurred_at: occurred_at,
          payment_method: payment_method,
          reference: reference.presence,
          description: transfer_movement_description(base: "Comision de pago: #{concept}", reference: reference),
        )
      end
    end

    notice_message = movement_kind == "expense" ? "Pago registrado correctamente." : "Credito registrado correctamente."
    redirect_to account_path(@account, movement_id: movement.id), notice: notice_message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to account_path(@account), alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def edit_movement
    @movement_concept = movement_concept_from_description(@movement.description)
    @movement_date = @movement.occurred_at&.in_time_zone("America/Caracas")&.to_date
  end

  def update_movement
    concept = params[:concept].to_s.strip
    return redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                       alert: "Indica el concepto del movimiento." if concept.blank?

    payment_date = parse_transfer_date(params[:payment_date])
    if payment_date.blank?
      return redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                         alert: "Indica una fecha valida para el movimiento."
    end

    amount = parse_transfer_decimal(params[:amount])
    unless amount.positive?
      return redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                         alert: "Indica un monto valido mayor a 0."
    end

    movement_kind = normalize_payment_movement_kind(params[:movement_kind])
    if movement_kind.blank?
      return redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                         alert: "Selecciona un tipo de movimiento valido (debito o credito)."
    end

    reference = params[:reference].to_s.strip
    if @account.account_type == "bank_account" && !valid_bank_reference?(reference)
      return redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                         alert: "La referencia debe tener exactamente 4 digitos."
    end

    caracas_now = Time.current.in_time_zone("America/Caracas")
    occurred_at = caracas_now.change(year: payment_date.year, month: payment_date.month, day: payment_date.day)
    payment_method = @account.account_type == "bank_account" ? "transfer" : nil

    @movement.update!(
      movement_kind: movement_kind,
      amount: amount,
      occurred_at: occurred_at,
      payment_method: payment_method,
      reference: reference.presence,
      description: transfer_movement_description(
        base: "#{movement_kind == 'expense' ? 'Pago' : 'Credito manual'}: #{concept}",
        reference: reference,
      ),
    )

    redirect_to account_path(@account, movement_id: @movement.id), notice: "Movimiento manual actualizado correctamente."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_movement_account_path(@account, movement_id: @movement.id),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  def destroy_movement
    movement_id = @movement.id
    @movement.destroy!

    redirect_to account_path(@account), notice: "Movimiento ##{movement_id} eliminado correctamente."
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => e
    redirect_to account_path(@account), alert: e.message.presence || "No se pudo eliminar el movimiento."
  end

  private

  def initialize_movement_filters
    @selected_fecha_desde = parse_filter_date(params[:fecha_desde])
    @selected_fecha_hasta = parse_filter_date(params[:fecha_hasta])

    if @selected_fecha_desde.present? && @selected_fecha_hasta.present? && @selected_fecha_desde > @selected_fecha_hasta
      @selected_fecha_desde, @selected_fecha_hasta = @selected_fecha_hasta, @selected_fecha_desde
    end

    @selected_fecha_desde_value = normalized_filter_date_value(params[:fecha_desde], @selected_fecha_desde)
    @selected_fecha_hasta_value = normalized_filter_date_value(params[:fecha_hasta], @selected_fecha_hasta)
    @movement_filters_applied = [
      params[:fecha_desde].to_s.strip,
      params[:fecha_hasta].to_s.strip,
    ].any?(&:present?)
  end

  def apply_movement_date_filters(scope)
    filtered_scope = scope

    if @selected_fecha_desde.present?
      filtered_scope = filtered_scope.where("occurred_at >= ?",
                                            @selected_fecha_desde.in_time_zone("America/Caracas").beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      filtered_scope = filtered_scope.where("occurred_at <= ?",
                                            @selected_fecha_hasta.in_time_zone("America/Caracas").end_of_day)
    end

    filtered_scope
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

  def build_movement_query_params
    {}.tap do |hash|
      hash[:fecha_desde] = @selected_fecha_desde_value if @selected_fecha_desde_value.present?
      hash[:fecha_hasta] = @selected_fecha_hasta_value if @selected_fecha_hasta_value.present?
    end
  end

  def parse_transfer_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr("/", "-"), "%d-%m-%Y") if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def parse_transfer_decimal(value)
    return 0.to_d if value.blank?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/\s/, "").gsub(/[^\d.,-]/, "")
    normalized = if cleaned.include?(",")
        cleaned.gsub(".", "").gsub(",", ".")
      else
        cleaned
      end

    BigDecimal(normalized)
  rescue ArgumentError
    0.to_d
  end

  def normalize_payment_movement_kind(raw_value)
    value = raw_value.to_s.strip.downcase
    return "expense" if value == "expense"
    return "income" if value == "income"

    nil
  end

  def suggested_transfer_amount(amount_from:, from_account:, to_account:, transfer_date:)
    return amount_from.to_d.round(2) if from_account.currency == to_account.currency

    from_rate = transfer_rate_to_ves(currency: from_account.currency, transfer_date: transfer_date)
    to_rate = transfer_rate_to_ves(currency: to_account.currency, transfer_date: transfer_date)
    return nil unless from_rate.positive? && to_rate.positive?

    (amount_from.to_d * from_rate / to_rate).round(2)
  end

  def transfer_rate_to_ves(currency:, transfer_date:)
    code = currency.to_s.upcase
    return 1.to_d if code == "VES"

    on_date = %w[USD EUR].include?(code) ? transfer_date : nil
    CurrencyConverter.rate_to_ves(code, on_date: on_date).to_d
  end

  def normalize_transfer_payment_method(value)
    normalized = value.to_s.strip
    return normalized if %w[third_party_transfer interbank_transfer mobile_payment].include?(normalized)

    nil
  end

  def valid_bank_reference?(value)
    value.to_s.match?(/\A\d{4}\z/)
  end

  def transfer_movement_description(base:, reference: nil)
    base
  end

  def transfer_commission_applicable?(payment_method)
    %w[interbank_transfer mobile_payment].include?(payment_method.to_s)
  end

  def calculated_transfer_commission(amount_from)
    (amount_from.to_d * 0.003).round(2)
  end

  def suggested_transfer_commission_amount(amount_from:, from_account:, commission_account:, transfer_date:)
    base_commission = calculated_transfer_commission(amount_from)
    return base_commission if commission_account.blank?
    return base_commission if from_account.currency == commission_account.currency

    from_rate = transfer_rate_to_ves(currency: from_account.currency, transfer_date: transfer_date)
    to_rate = transfer_rate_to_ves(currency: commission_account.currency, transfer_date: transfer_date)
    return nil unless from_rate.positive? && to_rate.positive?

    (base_commission * from_rate / to_rate).round(2)
  end

  def transfer_payment_method_label(payment_method)
    AccountMovement::PAYMENT_METHODS[payment_method.to_s] || payment_method.to_s.humanize
  end

  def transfer_payment_method_for(account, payment_method)
    account.account_type == "bank_account" ? payment_method : nil
  end

  def set_manual_movement
    @movement = @account.account_movements.find_by(id: params[:movement_id])
    return if @movement.present? && manual_account_movement_editable?(@movement)

    redirect_to account_path(@account), alert: "Solo puedes editar o eliminar movimientos manuales."
  end

  def set_movement_for_destroy
    @movement = @account.account_movements.find_by(id: params[:movement_id])
    return if @movement.present?

    redirect_to account_path(@account), alert: "No se encontro el movimiento seleccionado."
  end

  def manual_account_movement_editable?(movement)
    return false unless current_user_admin?
    return false if movement.blank?
    return false if movement.account_settlement_id.present? || movement.cambio_efectivo_id.present?

    description = movement.description.to_s
    !description.match?(/\[(?:DEBT|DP|VENTA|VENTA_DRAFT|FACTURA_COMPRA|PURCHASE_INVOICE|GASTO|ACCOUNT|AM|CASH_SHIFT|CAMBIO_EFECTIVO):\d+\]/i)
  end

  def movement_concept_from_description(description)
    text = description.to_s.strip
    text = text.gsub(/\s*-\s*Ref\s+[^\s\]]+/i, "").strip
    text = text.sub(/\A(?:Pago|Credito\s+manual):\s*/i, "").strip
    text.presence || "Movimiento manual"
  end

  def set_account
    @account = accounts_visible_scope.find(params[:id])
  end

  def load_transfer_support_data
    return @transfer_accounts_payload = [] unless current_user_admin?

    @transfer_accounts_payload = current_business.accounts.where(active: true).order(:name).map do |account|
      {
        id: account.id,
        name: account.name,
        display_name: account.name_with_cash_role,
        currency: account.currency,
        symbol: account.currency_symbol,
        balance: account.balance.to_d.to_f,
        account_type: account.account_type,
      }
    end

    @transfer_latest_rates = Account::CURRENCIES.keys.each_with_object({}) do |currency, hash|
      hash[currency] = CurrencyConverter.rate_to_ves(currency, on_date: nil).to_d.to_f
    end
    @transfer_latest_rates["VES"] = 1.0
  end

  def ensure_accounts_management_allowed!
    return if current_user_admin?

    deny_access('Solo el administrador puede gestionar cuentas o registrar movimientos.')
  end

  def accounts_visible_scope
    scope = current_business.accounts
    return scope if current_user_admin?
    return scope.none unless current_user_manager?

    scope.where(
      'accounts.account_type IN (:types) OR LOWER(accounts.name) LIKE :payall',
      types: Account::SPECIAL_ACCOUNT_TYPES + ['cash_box'],
      payall: '%payall%'
    )
  end

  def account_params
    params.require(:account).permit(
      :name,
      :account_type,
      :currency,
      :balance,
      :cash_role,
      :theme_color,
      :active,
      :settlement_account_id,
      :notes,
      :logo,
      :small_logo,
      :payment_method_image
    )
  end

  def set_bcv_rate
    @bcv_rate = TasaCambio.latest_value("Dolar BCV")
    @usdt_rate = TasaCambio.latest_value("USDT") || TasaCambio.latest_value("USDT Bybit")
  end

  def load_bank_accounts_ves
    @bank_accounts_ves = current_business.accounts
                                         .where(account_type: "bank_account", currency: "VES")
                                         .order(:name)
  end

  def build_biopago_pending_close_info(account)
    return default_biopago_close_info unless account&.account_type == "biopago"

    oldest_pending_settlement = account.account_settlements
                                       .where(processed_at: nil)
                                       .order(period_start_at: :asc, closed_at: :asc, id: :asc)
                                       .first

    if oldest_pending_settlement.present?
      period_start = oldest_pending_settlement.period_start_at || oldest_pending_settlement.closed_at
      period_day = period_start&.in_time_zone("America/Caracas")&.to_date

      return {
               day: period_day,
               total: oldest_pending_settlement.total_amount.to_d.round(2),
               movements_count: oldest_pending_settlement.movements_count,
               closable: oldest_pending_settlement.total_amount.to_d.positive?,
             }
    end

    today_start = closure_reference_day_start_caracas

    pending_before_today = account.account_movements
                                  .where(account_settlement_id: nil)
                                  .where("occurred_at < ?", today_start)

    oldest_movement = pending_before_today.to_a.min_by do |movement|
      occurred_at_caracas = movement.occurred_at&.in_time_zone("America/Caracas")
      [occurred_at_caracas&.to_date, occurred_at_caracas, movement.id]
    end
    return default_biopago_close_info if oldest_movement.blank?

    oldest_day = oldest_movement.occurred_at.in_time_zone("America/Caracas").to_date
    day_start = oldest_day.in_time_zone("America/Caracas").beginning_of_day
    day_end = oldest_day.in_time_zone("America/Caracas").end_of_day

    day_scope = account.account_movements
                       .where(account_settlement_id: nil)
                       .where(occurred_at: day_start..day_end)

    day_total = day_scope.sum(
      Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
    ).to_d.round(2)

    {
      day: oldest_day,
      total: day_total,
      movements_count: day_scope.count,
      closable: day_total.positive?,
    }
  end

  def default_biopago_close_info
    {
      day: nil,
      total: 0.to_d,
      movements_count: 0,
      closable: false,
    }
  end
end
