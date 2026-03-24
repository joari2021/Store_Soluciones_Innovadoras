class UpdateSupplierIdentificationAndPaymentFields < ActiveRecord::Migration[7.1]
  def change
    rename_column :suppliers, :ruc, :rif
    add_column :suppliers, :nro_cuenta, :string
    add_column :suppliers, :telefono_pago_movil, :string
  end
end
