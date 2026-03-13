class AccountsController < ApplicationController
  before_action :require_business
  before_action :set_account, only: %i[show edit update destroy set_primary unset_primary]
  before_action :set_bcv_rate, only: %i[index show]
  before_action :load_bank_accounts_ves, only: %i[new edit create update]

  def index
    @accounts = current_business.accounts.order(name: :asc)
    totals = current_business.accounts.group(:currency).sum(:balance)
    @currency_totals = Account::CURRENCIES.keys.index_with { |code| totals[code] || 0 }
  end

  def show
    if @account.settlement_enabled?
      pending_scope = @account.account_movements.where(account_settlement_id: nil)
      @account_movements = pending_scope
      @pending_movements_count = pending_scope.count
      @pending_movements_total = pending_scope.sum(
        Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
      ).to_d
      @pending_period_start = pending_scope.minimum(:occurred_at)
      @pending_period_end = pending_scope.maximum(:occurred_at)
      @account_settlements = @account.account_settlements.where(processed_at: nil).order(closed_at: :desc)
      @processed_settlements_count = @account.account_settlements.where.not(processed_at: nil).count
      return
    end

    @account_movements = @account.account_movements
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
      :notes
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
