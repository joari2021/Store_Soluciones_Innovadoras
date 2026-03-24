class CreateCashShiftsAndLinkSales < ActiveRecord::Migration[7.1]
  def change
    create_table :cash_shifts do |t|
      t.references :business, null: false, foreign_key: true
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'open'
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.decimal :opening_balance_ves, precision: 14, scale: 2, null: false, default: 0
      t.decimal :opening_balance_usd, precision: 14, scale: 2, null: false, default: 0
      t.decimal :declared_closing_ves, precision: 14, scale: 2
      t.decimal :declared_closing_usd, precision: 14, scale: 2
      t.text :opening_notes
      t.text :closing_notes

      t.timestamps
    end

    add_index :cash_shifts, %i[business_id status]
    add_index :cash_shifts, :opened_at

    add_reference :ventas, :cash_shift, foreign_key: true
    add_reference :ventas, :user, foreign_key: true
  end
end
