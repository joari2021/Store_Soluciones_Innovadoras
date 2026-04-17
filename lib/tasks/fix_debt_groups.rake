namespace :debt do
  desc 'Corrige y agrupa deudas existentes para que todas las activas de un cliente y moneda tengan el prefijo [GRP:ID] del grupo'
  task fix_groups: :environment do
    Debt.where.not(currency: 'USDT').group_by { |d| [d.cliente_id, d.currency] }.each do |(cliente_id, currency), deudas|
      activas = deudas.select { |d| d.balance > 0.01 }
      next if activas.empty? || activas.all? { |d| d.name.to_s =~ /\[GRP:\d+\]/ }
      group_id = activas.first.id
      activas.each do |deuda|
        base = deuda.name.to_s.sub(/\[GRP:\d+\]\s*/, '')
        deuda.update_columns(name: "[GRP:#{group_id}] #{base}")
        puts "Actualizada deuda ##{deuda.id} => [GRP:#{group_id}] #{base}"
      end
    end
    puts 'Agrupación de deudas activas completada.'
  end
end
