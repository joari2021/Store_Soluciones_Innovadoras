class AccountSettlementsController < ApplicationController
  before_action :require_business
  before_action :set_account
  before_action :set_settlement, only: %i[show update]

  def index
    @processed_settlements = @account.account_settlements
                                     .where.not(processed_at: nil)
                                     .order(processed_at: :desc)
  end

  def show
    @settlement_movements = @settlement.account_movements.order(occurred_at: :desc, created_at: :desc)
  end

  def create
    unless @account.settlement_enabled?
      redirect_to account_path(@account), alert: 'Esta cuenta no admite cierres.'
      return
    end

    if @account.settlement_account_required? && @account.settlement_account.blank?
      redirect_to account_path(@account), alert: 'Asigna una cuenta bancaria en Bs antes de crear un cierre.'
      return
    end

    pending_scope = @account.account_movements.where(account_settlement_id: nil)
    pending_total = pending_scope.sum(
      Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
    ).to_d

    if pending_total <= 0
      redirect_to account_path(@account), alert: 'No hay movimientos pendientes por cerrar.'
      return
    end

    pending_count = pending_scope.count
    period_start = pending_scope.minimum(:occurred_at)
    period_end = pending_scope.maximum(:occurred_at)

    AccountSettlement.transaction do
      settlement = @account.account_settlements.create!(
        total_amount: pending_total,
        movements_count: pending_count,
        closed_at: Time.current,
        period_start_at: period_start,
        period_end_at: period_end,
        settlement_account: @account.settlement_account
      )

      pending_scope.update_all(account_settlement_id: settlement.id, updated_at: Time.current)
      @account.recalculate_balance!
    end

    redirect_to account_path(@account), notice: 'Cierre generado.'
  end

  def update
    if @settlement.processed?
      redirect_to account_path(@account), alert: 'Este cierre ya fue procesado.'
      return
    end

    credited_amount = parse_decimal(settlement_params[:credited_amount])
    commission_amount = parse_decimal(settlement_params[:commission_amount])

    if credited_amount <= 0
      redirect_to account_path(@account), alert: 'El monto acreditado debe ser mayor a cero.'
      return
    end

    if commission_amount.negative?
      redirect_to account_path(@account), alert: 'La comision no puede ser negativa.'
      return
    end

    settlement_account = @account.settlement_account
    if settlement_account.blank?
      redirect_to account_path(@account), alert: 'Asigna una cuenta bancaria en Bs para procesar el cierre.'
      return
    end

    unless settlement_account.account_type == 'bank_account' && settlement_account.currency == 'VES'
      redirect_to account_path(@account), alert: 'La cuenta asignada debe ser bancaria en Bs.'
      return
    end

    base_date = @settlement.period_end_at || @settlement.closed_at
    settlement_date = base_date.in_time_zone('Caracas').to_date + 1.day
    occurred_at = Time.zone.parse(settlement_date.to_s)

    AccountSettlement.transaction do
      @settlement.update!(
        credited_amount: credited_amount,
        commission_amount: commission_amount,
        processed_at: Time.current,
        settlement_account: settlement_account,
        settlement_date: settlement_date
      )

      if settlement_account.present?
        settlement_account.account_movements.create!(
          movement_kind: 'income',
          amount: credited_amount,
          description: "Liquidacion #{@account.account_type_label} (cierre ##{@settlement.id})",
          occurred_at: occurred_at,
          payment_method: 'settlement'
        )

        if commission_amount.positive?
          settlement_account.account_movements.create!(
            movement_kind: 'expense',
            amount: commission_amount,
            description: "Comision #{@account.account_type_label} (cierre ##{@settlement.id})",
            occurred_at: occurred_at,
            payment_method: 'settlement'
          )
        end
      end
    end

    redirect_to account_path(@account), notice: 'Cierre procesado.'
  end

  private

  def set_account
    @account = current_business.accounts.find(params[:account_id])
  end

  def set_settlement
    @settlement = @account.account_settlements.find(params[:id])
  end

  def settlement_params
    params.require(:account_settlement).permit(:credited_amount, :commission_amount)
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
end
