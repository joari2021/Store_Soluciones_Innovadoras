class AddCasheaFinancingFieldsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :cashea_line_mode, :string, default: "cotidiana", null: false
    add_column :accounts, :cashea_cotidiana_installments, :integer, default: 1, null: false
  end
end
