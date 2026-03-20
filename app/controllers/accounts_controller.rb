class AccountsController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_account, only: %i[show edit update destroy set_primary unset_primary]
  before_action :set_bcv_rate, only: %i[index show]
  before_action :load_bank_accounts_ves, only: %i[new edit create update]

  def index
    @accounts = current_business.accounts.with_attached_logo.order(name: :asc)
    totals = current_business.accounts.group(:currency).sum(:balance)
    @currency_totals = Account::CURRENCIES.keys.index_with { |code| totals[code] || 0 }
  end

  def show
    initialize_movement_filters

    if @account.settlement_enabled?
      pending_scope = apply_movement_date_filters(@account.account_movements.where(account_settlement_id: nil))
      @pending_movements_count = pending_scope.count
      @pending_movements_total = pending_scope.sum(
        Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
      ).to_d
      @pending_period_start = pending_scope.minimum(:occurred_at)
      @pending_period_end = pending_scope.maximum(:occurred_at)
      @account_settlements = @account.account_settlements.where(processed_at: nil).order(closed_at: :desc)
      @processed_settlements_count = @account.account_settlements.where.not(processed_at: nil).count

      ordered_scope = pending_scope.order(occurred_at: :desc, id: :desc)
      @pagy, @account_movements = pagy_countless(ordered_scope, items: 24)
      @movement_query_params = build_movement_query_params
      return
    end

    ordered_scope = apply_movement_date_filters(@account.account_movements).order(occurred_at: :desc, id: :desc)
    @pagy, @account_movements = pagy_countless(ordered_scope, items: 24)
    @movement_query_params = build_movement_query_params
  end

  def new
    @account = current_business.accounts.new(account_type: 'bank_account', currency: 'USD', theme_color: 'sky',
                                             balance: 0, active: true)
  end

  def create
    @account = current_business.accounts.new(account_params)

    if @account.save
      redirect_to accounts_path, notice: 'Cuenta creada'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      redirect_to account_path(@account), notice: 'Cuenta actualizada'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.destroy
    redirect_to accounts_path, notice: 'Cuenta eliminada'
  end

  def set_primary
    unless @account.account_type == 'bank_account'
      redirect_to accounts_path, alert: 'Solo cuentas bancarias pueden ser principales.'
      return
    end

    if @account.update(is_primary: true)
      redirect_to accounts_path, notice: 'Cuenta principal actualizada.'
    else
      redirect_to accounts_path, alert: @account.errors.full_messages.to_sentence
    end
  end

  def unset_primary
    unless @account.account_type == 'bank_account'
      redirect_to accounts_path, alert: 'Solo cuentas bancarias pueden ser principales.'
      return
    end

    if @account.update(is_primary: false)
      redirect_to accounts_path, notice: 'Cuenta principal removida.'
    else
      redirect_to accounts_path, alert: @account.errors.full_messages.to_sentence
    end
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
      params[:fecha_hasta].to_s.strip
    ].any?(&:present?)
  end

  def apply_movement_date_filters(scope)
    filtered_scope = scope

    if @selected_fecha_desde.present?
      filtered_scope = filtered_scope.where('occurred_at >= ?',
                                            @selected_fecha_desde.in_time_zone('America/Caracas').beginning_of_day)
    end

    if @selected_fecha_hasta.present?
      filtered_scope = filtered_scope.where('occurred_at <= ?',
                                            @selected_fecha_hasta.in_time_zone('America/Caracas').end_of_day)
    end

    filtered_scope
  end

  def parse_filter_date(raw_value)
    return nil if raw_value.blank?

    normalized = raw_value.to_s.strip
    return Date.strptime(normalized.tr('/', '-'), '%d-%m-%Y') if normalized.match?(%r{\A\d{1,2}[/-]\d{1,2}[/-]\d{4}\z})
    return Date.iso8601(normalized) if normalized.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.parse(normalized)
  rescue ArgumentError
    nil
  end

  def normalized_filter_date_value(raw_value, parsed_value)
    return parsed_value.strftime('%d-%m-%Y') if parsed_value.present?

    raw_value.to_s.strip
  end

  def build_movement_query_params
    {}.tap do |hash|
      hash[:fecha_desde] = @selected_fecha_desde_value if @selected_fecha_desde_value.present?
      hash[:fecha_hasta] = @selected_fecha_hasta_value if @selected_fecha_hasta_value.present?
    end
  end

  def set_account
    @account = current_business.accounts.find(params[:id])
  end

  def account_params
    params.require(:account).permit(
      :name,
      :account_type,
      :currency,
      :balance,
      :theme_color,
      :active,
      :settlement_account_id,
      :notes,
      :logo,
      :payment_method_image
    )
  end

  def set_bcv_rate
    @bcv_rate = TasaCambio.latest_value('Dolar BCV')
    @usdt_rate = TasaCambio.latest_value('USDT') || TasaCambio.latest_value('USDT Bybit')
  end

  def load_bank_accounts_ves
    @bank_accounts_ves = current_business.accounts
                                         .where(account_type: 'bank_account', currency: 'VES')
                                         .order(:name)
  end
end
