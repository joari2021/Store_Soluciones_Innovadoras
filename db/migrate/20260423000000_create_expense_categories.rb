class CreateExpenseCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :expense_categories do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :expense_categories, [:business_id, :name], unique: true

    add_reference :expenses, :expense_category, foreign_key: true
  end
end
