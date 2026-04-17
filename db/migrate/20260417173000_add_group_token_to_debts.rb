class AddGroupTokenToDebts < ActiveRecord::Migration[7.1]
  class MigrationDebt < ActiveRecord::Base
    self.table_name = 'debts'
  end

  def up
    add_column :debts, :group_token, :string
    add_index :debts, [:business_id, :debt_kind, :group_token], name: 'idx_debts_group_token'

    say_with_time 'Backfilling debts.group_token from legacy grouping' do
      MigrationDebt.reset_column_information

      MigrationDebt.find_each do |debt|
        token = legacy_group_token_for(debt)
        debt.update_columns(group_token: token)
      end
    end
  end

  def down
    remove_index :debts, name: 'idx_debts_group_token'
    remove_column :debts, :group_token
  end

  private

  def legacy_group_token_for(debt)
    match = debt.name.to_s.match(/\A\[GRP:(\d+)\]\s*/)
    return "legacy-#{match[1]}" if match.present?

    "legacy-debt-#{debt.id}"
  end
end
