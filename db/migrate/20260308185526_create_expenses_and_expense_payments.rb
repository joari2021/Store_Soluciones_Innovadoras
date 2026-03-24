class CreateExpensesAndExpensePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :expenses do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :expense_type, null: false, default: 'variable'
      t.string :frequency, null: false, default: 'once'
      t.date :start_date
      t.date :end_date
      t.date :next_due_on
      t.date :last_paid_on
      t.integer :occurrences_limit
      t.integer :payments_count, null: false, default: 0
      t.decimal :amount, precision: 14, scale: 2
      t.string :currency, default: 'USD'
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    create_table :expense_payments do |t|
      t.references :expense, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method
      t.string :reference
      t.datetime :occurred_at, null: false
      t.text :notes
      t.timestamps
    end
  end
end
