class AccountSettlement < ApplicationRecord
  belongs_to :account
  belongs_to :settlement_account, class_name: 'Account', optional: true
  has_many :account_movements, dependent: :nullify

  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :movements_count, numericality: { greater_than_or_equal_to: 0 }
  validates :closed_at, presence: true
  validates :credited_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :commission_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def processed?
    processed_at.present?
  end

  def self.sync_pending_movements_for_account!(account)
    return if account.blank?

    pending_settlements = account.account_settlements
                                 .where(processed_at: nil)
                                 .order(Arel.sql('COALESCE(period_start_at, closed_at) ASC'), closed_at: :asc, id: :asc)
                                 .to_a
    return if pending_settlements.empty?

    transaction do
      pending_settlements.each do |settlement|
        period_start = settlement.period_start_at || settlement.closed_at
        period_end = settlement.period_end_at || settlement.closed_at
        next if period_start.blank? || period_end.blank?

        account.account_movements
               .where(account_settlement_id: nil)
               .where(occurred_at: period_start..period_end)
               .update_all(account_settlement_id: settlement.id, updated_at: Time.current)

        assigned_scope = account.account_movements.where(account_settlement_id: settlement.id)
        assigned_count = assigned_scope.count
        next if assigned_count.zero?

        net_total = assigned_scope.sum(
          Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
        ).to_d.round(2)

        settlement.update_columns(
          total_amount: net_total,
          movements_count: assigned_count,
          updated_at: Time.current,
        )
      end
    end
  end
end
