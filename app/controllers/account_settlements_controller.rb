class AccountSettlementsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_account
  before_action :set_settlement, only: %i[show update]

  def index
    @processed_settlements = @account.account_settlements.where.not(processed_at: nil)
    @processed_settlements = if @account.account_type == 'biopago'
                               @processed_settlements.order(period_start_at: :asc, processed_at: :asc)
                             else
                               @processed_settlements.order(processed_at: :desc)
                             end
  end

  def show
    @settlement_movements = @settlement.account_movements.order(occurred_at: :desc, created_at: :desc)

    latest_movement = @settlement_movements.first
    @settlement_latest_movement_at = latest_movement&.occurred_at&.in_time_zone('America/Caracas')
    @suggested_settlement_date = (@settlement_latest_movement_at&.to_date || Time.current.in_time_zone('America/Caracas').to_date) + 1.day
  end

  def create
    unless @account.account_type == 'biopago'
      return redirect_to account_path(@account), alert: 'Los cierres de esta cuenta se ejecutan al cerrar turno.'
    end

    existing_pending_settlement = @account.account_settlements
                                          .where(processed_at: nil)
                                          .order(period_start_at: :asc, closed_at: :asc, id: :asc)
                                          .first

    if existing_pending_settlement.present?
      period_label = existing_pending_settlement.period_start_at&.in_time_zone('America/Caracas')&.strftime('%d/%m/%Y')
      message = if period_label.present?
                  "Ya existe un cierre pendiente de Biopago para el #{period_label}. Debes procesarlo primero."
                else
                  'Ya existe un cierre pendiente de Biopago. Debes procesarlo primero.'
                end

      return redirect_to account_account_settlement_path(@account, existing_pending_settlement), alert: message
    end

    today_start = closure_reference_day_start_caracas

    pending_before_today = @account.account_movements
                                   .where(account_settlement_id: nil)
                                   .where('occurred_at < ?', today_start)

    if pending_before_today.blank?
      return redirect_to account_path(@account),
                         alert: 'No hay movimientos pendientes de dias anteriores para cerrar en Biopago.'
    end

    oldest_movement = pending_before_today.to_a.min_by do |movement|
      occurred_at_caracas = movement.occurred_at&.in_time_zone('America/Caracas')
      [occurred_at_caracas&.to_date, occurred_at_caracas, movement.id]
    end

    oldest_day = oldest_movement.occurred_at.in_time_zone('America/Caracas').to_date
    day_start = oldest_day.in_time_zone('America/Caracas').beginning_of_day
    day_end = oldest_day.in_time_zone('America/Caracas').end_of_day

    day_scope = @account.account_movements
                        .where(account_settlement_id: nil)
                        .where(occurred_at: day_start..day_end)
                        .order(:occurred_at)

    movements_count = day_scope.count
    if movements_count.zero?
      return redirect_to account_path(@account),
                         alert: 'No se encontraron movimientos pendientes para el dia seleccionado.'
    end

    total_amount = day_scope.sum(
      Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
    ).to_d.round(2)

    unless total_amount.positive?
      return redirect_to account_path(@account),
                         alert: 'El total neto pendiente del dia no es mayor a cero y no puede cerrarse.'
    end

    settlement = nil

    AccountSettlement.transaction do
      settlement = @account.account_settlements.create!(
        total_amount: total_amount,
        movements_count: movements_count,
        closed_at: Time.current,
        period_start_at: day_start,
        period_end_at: day_end,
        settlement_account: (@account.settlement_account if @account.settlement_account.present?)
      )

      day_scope.update_all(account_settlement_id: settlement.id, updated_at: Time.current)
      @account.recalculate_balance!
    end

    redirect_to account_account_settlement_path(@account, settlement),
                notice: "Cierre diario de Biopago generado para el #{oldest_day.strftime('%d/%m/%Y')}."
  end

  def update
    if @settlement.processed?
      return redirect_to account_account_settlement_path(@account, @settlement),
                         alert: 'Este cierre ya fue procesado.'
    end

    credited_amount = parse_decimal(settlement_params[:credited_amount]).to_d.round(2)
    commission_amount = parse_decimal(settlement_params[:commission_amount]).to_d.round(2)
    settlement_date = parse_settlement_date(settlement_params[:settlement_date])

    if credited_amount.negative? || commission_amount.negative?
      return redirect_to account_account_settlement_path(@account, @settlement),
                         alert: 'Acreditado y comision deben ser montos positivos.'
    end

    if settlement_date.blank?
      return redirect_to account_account_settlement_path(@account, @settlement),
                         alert: 'Indica una fecha valida para procesar el cierre.'
    end

    settlement_account = @settlement.settlement_account || @account.settlement_account
    if @account.settlement_account_required? && settlement_account.blank?
      return redirect_to account_account_settlement_path(@account, @settlement),
                         alert: 'Asigna una cuenta bancaria en Bs antes de procesar este cierre.'
    end

    processed_at = Time.current
    processed_at_caracas = processed_at.in_time_zone('America/Caracas')
    occurred_at = ActiveSupport::TimeZone['America/Caracas'].local(
      settlement_date.year,
      settlement_date.month,
      settlement_date.day,
      processed_at_caracas.hour,
      processed_at_caracas.min,
      processed_at_caracas.sec
    )

    AccountSettlement.transaction do
      @settlement.update!(
        credited_amount: credited_amount,
        commission_amount: commission_amount,
        processed_at: processed_at,
        settlement_date: settlement_date,
        settlement_account: settlement_account
      )

      if settlement_account.present? && credited_amount.positive?
        settlement_account.account_movements.create!(
          movement_kind: 'income',
          amount: credited_amount,
          description: "Liquidacion #{@account.account_type_label} (cierre ##{@settlement.id}) [ACCOUNT:#{@account.id}]",
          occurred_at: occurred_at,
          payment_method: 'settlement'
        )
      end

      if settlement_account.present? && commission_amount.positive?
        settlement_account.account_movements.create!(
          movement_kind: 'expense',
          amount: commission_amount,
          description: "Comision #{@account.account_type_label} (cierre ##{@settlement.id}) [ACCOUNT:#{@account.id}]",
          occurred_at: occurred_at,
          payment_method: 'settlement'
        )
      end
    end

    redirect_to account_account_settlement_path(@account, @settlement),
                notice: 'Cierre procesado correctamente.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to account_account_settlement_path(@account, @settlement),
                alert: e.record&.errors&.full_messages&.to_sentence.presence || e.message
  end

  private

  def set_account
    @account = current_business.accounts.find(params[:account_id])
  end

  def set_settlement
    @settlement = @account.account_settlements.find(params[:id])
  end

  def settlement_params
    params.require(:account_settlement).permit(:credited_amount, :commission_amount, :settlement_date)
  end

  def parse_decimal(value)
    return 0.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    compact = value.to_s.strip.gsub(/\s+/, '').gsub(/[^\d.,-]/, '')
    return 0.to_d if compact.empty?

    normalized = if compact.include?(',')
                   compact.gsub('.', '').tr(',', '.')
                 elsif compact.match?(/^\d{1,3}(\.\d{3})+$/)
                   compact.tr('.', '')
                 else
                   compact
                 end

    BigDecimal(normalized)
  rescue ArgumentError
    0.to_d
  end

  def parse_settlement_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr('/', '-'), '%d-%m-%Y') if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end
end
