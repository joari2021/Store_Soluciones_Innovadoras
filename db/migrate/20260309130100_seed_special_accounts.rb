class SeedSpecialAccounts < ActiveRecord::Migration[7.1]
  def up
    Business.reset_column_information
    Account.reset_column_information

    say_with_time 'Seeding special payment accounts' do
      Business.find_each do |business|
        Account.ensure_special_accounts!(business)
      end
    end
  end

  def down
    # No rollback for data seed
  end
end
