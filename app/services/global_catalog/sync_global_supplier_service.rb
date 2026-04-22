module GlobalCatalog
  class SyncGlobalSupplierService
    def initialize(global_supplier)
      @global_supplier = global_supplier
    end

    def call
      mapped_suppliers.find_each do |local_supplier|
        local_supplier.update_columns(
          nombre: @global_supplier.name,
          rif: @global_supplier.rif,
          telefono: @global_supplier.phone,
          telefono_pago_movil: @global_supplier.mobile_payment_phone,
          email: @global_supplier.email,
          direccion: @global_supplier.address,
          nro_cuenta: @global_supplier.bank_account_number,
          pricing_currency_priority: @global_supplier.pricing_currency_priority,
          default_exento: @global_supplier.default_exento,
          updated_at: Time.current,
        )
      end
    end

    private

    def mapped_suppliers
      Supplier.where(global_supplier_id: @global_supplier.id)
    end
  end
end
