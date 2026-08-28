namespace :accounts do
  desc "Reasigna pagos apuntando a cuentas 'Transferencia de deuda' y elimina esas cuentas"
  task remove_transfer_accounts: :environment do
    transfer_accounts = Account.where("name LIKE ?", "Transferencia de deuda%")
    if transfer_accounts.empty?
      puts "No se encontraron cuentas 'Transferencia de deuda'."
      next
    end

    transfer_accounts.find_each do |ta|
      begin
        business_name = ta.business&.name.to_s
        puts "Procesando cuenta id=#{ta.id} negocio=#{business_name} currency=#{ta.currency} name=#{ta.name}"

        target = ta.business.accounts.where(account_type: 'cash_box', currency: ta.currency, active: true).order(:id).first ||
                 ta.business.accounts.where(account_type: 'cash_box', currency: ta.currency).order(:id).first ||
                 ta.business.accounts.where(account_type: 'cash_box').order(:id).first

        if target.nil?
          puts "  No se encontró caja destino para negocio=#{business_name}. Saltando cuenta id=#{ta.id}."
          next
        end

        DebtPayment.transaction do
          payments = DebtPayment.where(account_id: ta.id)
          puts "  Reasignando #{payments.count} pagos a cuenta id=#{target.id} name=#{target.name}"
          payments.find_each { |p| p.update!(account_id: target.id) }
          ta.destroy!
          puts "  Cuenta eliminada id=#{ta.id}"
        end
      rescue => e
        puts "  Error al procesar cuenta id=#{ta.id}: #{e.message}"
      end
    end
  end
end
