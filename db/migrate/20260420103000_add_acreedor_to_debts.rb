class AddAcreedorToDebts < ActiveRecord::Migration[7.1]
  def up
    add_column :debts, :acreedor, :string
    add_index :debts, [:business_id, :debt_kind, :acreedor], name: "index_debts_on_business_kind_acreedor"

    execute <<~SQL.squish
      UPDATE debts
      SET acreedor = NULLIF(TRIM(name), '')
      WHERE debt_kind = 'payable'
        AND (acreedor IS NULL OR TRIM(acreedor) = '')
    SQL
  end

  def down
    remove_index :debts, name: "index_debts_on_business_kind_acreedor"
    remove_column :debts, :acreedor
  end
end
