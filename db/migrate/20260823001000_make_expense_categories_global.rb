class MakeExpenseCategoriesGlobal < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE expense_categories
      SET name = TRIM(name)
      WHERE name <> TRIM(name)
    SQL

    execute <<~SQL
      WITH canonical AS (
        SELECT LOWER(TRIM(name)) AS normalized_name, MIN(id) AS canonical_id
        FROM expense_categories
        GROUP BY LOWER(TRIM(name))
      ), duplicates AS (
        SELECT ec.id AS duplicate_id, c.canonical_id
        FROM expense_categories ec
        INNER JOIN canonical c ON LOWER(TRIM(ec.name)) = c.normalized_name
        WHERE ec.id <> c.canonical_id
      )
      UPDATE expenses e
      SET expense_category_id = d.canonical_id
      FROM duplicates d
      WHERE e.expense_category_id = d.duplicate_id
    SQL

    execute <<~SQL
      WITH canonical AS (
        SELECT LOWER(TRIM(name)) AS normalized_name, MIN(id) AS canonical_id
        FROM expense_categories
        GROUP BY LOWER(TRIM(name))
      ), duplicates AS (
        SELECT ec.id AS duplicate_id
        FROM expense_categories ec
        INNER JOIN canonical c ON LOWER(TRIM(ec.name)) = c.normalized_name
        WHERE ec.id <> c.canonical_id
      )
      DELETE FROM expense_categories ec
      USING duplicates d
      WHERE ec.id = d.duplicate_id
    SQL

    remove_index :expense_categories, name: 'index_expense_categories_on_business_id_and_name'
    change_column_null :expense_categories, :business_id, true
    add_index :expense_categories, 'LOWER(name)', unique: true, name: 'index_expense_categories_on_lower_name'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'No se puede revertir automaticamente la unificacion global de categorias de gastos'
  end
end
