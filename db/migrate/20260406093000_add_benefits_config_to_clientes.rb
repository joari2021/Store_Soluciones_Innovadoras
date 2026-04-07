class AddBenefitsConfigToClientes < ActiveRecord::Migration[7.1]
  def change
    add_column :clientes, :benefits_config, :jsonb, default: {}, null: false
  end
end
