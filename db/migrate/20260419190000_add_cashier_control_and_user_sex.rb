class AddCashierControlAndUserSex < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :sex, :string, default: 'male', null: false
    add_index :users, :sex

    add_reference :cash_shifts,
                  :active_cashier,
                  foreign_key: { to_table: :users },
                  index: true
  end
end
