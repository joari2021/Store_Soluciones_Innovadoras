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
    redirect_to account_path(@account), alert: 'Los cierres de esta cuenta se ejecutan al cerrar turno.'
  end

  def update
    redirect_to account_path(@account), alert: 'Los cierres de esta cuenta se ejecutan al cerrar turno.'
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
