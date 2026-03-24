class CreateDebtsAndDebtPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :debts do |t|
      t.references :business, null: false, foreign_key: true
      t.string :debt_kind, null: false, default: 'receivable'
      t.string :name, null: false
      t.text :description
      t.string :reference
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :currency, null: false, default: 'USD'
      t.date :issued_on
      t.date :due_on
      t.bigint :cliente_id
      t.bigint :supplier_id
      t.string :counterparty_name
      t.timestamps
    end

    add_index :debts, :debt_kind
    add_index :debts, :due_on
    add_index :debts, :issued_on
    add_index :debts, :cliente_id
    add_index :debts, :supplier_id
    add_foreign_key :debts, :clientes
    add_foreign_key :debts, :suppliers

    create_table :debt_payments do |t|
      t.references :debt, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method
      t.string :reference
      t.datetime :occurred_at, null: false
      t.text :notes
      t.timestamps
    end

    add_index :debt_payments, :occurred_at
  end
end
