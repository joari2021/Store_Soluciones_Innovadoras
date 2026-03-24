class ChangeDebtPaymentsOccurredAtToDate < ActiveRecord::Migration[7.1]
  def up
    if postgresql_adapter?
      change_column :debt_payments, :occurred_at, :date, using: 'occurred_at::date'
    else
      change_column :debt_payments, :occurred_at, :date
    end
  end

  def down
    if postgresql_adapter?
      change_column :debt_payments, :occurred_at, :datetime, using: 'occurred_at::timestamp'
    else
      change_column :debt_payments, :occurred_at, :datetime
    end
  end

  private

  def postgresql_adapter?
    connection.adapter_name.to_s.downcase.include?('postgres')
  end
end
