namespace :debt do
  desc 'Migra deudas por cobrar en VES a USD usando tasa historica (deuda: emision, pagos: fecha de pago)'
  task migrate_receivable_ves_to_usd: :environment do
    business_id = ENV['BUSINESS_ID'].presence
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'false'))

    scope = Debt
            .excluding_service_cost_records
            .where(debt_kind: 'receivable', currency: 'VES')
            .includes(:debt_payments)
            .order(:id)

    scope = scope.where(business_id: business_id.to_i) if business_id.present?

    puts "Iniciando migracion VES->USD (receivable). BUSINESS_ID=#{business_id || 'ALL'} DRY_RUN=#{dry_run}"

    debt_count = 0
    payment_count = 0
    skipped_debts = []
    skipped_payments = []

    runner = lambda do
      scope.find_each do |debt|
        issued_on = debt.issued_on || debt.created_at&.to_date || Date.current

        debt_conversion = CurrencyConverter.convert(
          amount: debt.amount.to_d,
          from_currency: 'VES',
          to_currency: 'USD',
          on_date: issued_on
        )

        converted_debt_amount = debt_conversion&.dig(:amount).to_d
        if converted_debt_amount <= 0
          skipped_debts << debt.id
          puts "[SKIP DEBT ##{debt.id}] No se pudo convertir monto deuda #{debt.amount} VES a USD en fecha #{issued_on}."
          next
        end

        puts "[DEBT ##{debt.id}] #{debt.amount.to_d.round(2)} VES -> #{converted_debt_amount.round(2)} USD (#{issued_on})"

        unless dry_run
          debt.update_columns(
            amount: converted_debt_amount.round(2),
            currency: 'USD',
            updated_at: Time.current
          )
        end

        debt_count += 1

        debt.debt_payments.order(:id).each do |payment|
          occurred_on = payment.occurred_at || payment.created_at&.to_date || Date.current

          payment_conversion = CurrencyConverter.convert(
            amount: payment.amount.to_d,
            from_currency: payment.currency,
            to_currency: 'USD',
            on_date: occurred_on
          )

          converted_payment_amount = payment_conversion&.dig(:amount).to_d
          payment_rate = payment_conversion&.dig(:rate).to_d

          if converted_payment_amount <= 0 || payment_rate <= 0
            skipped_payments << payment.id
            puts "[SKIP PAYMENT ##{payment.id}] No se pudo convertir pago #{payment.amount} #{payment.currency} a USD en fecha #{occurred_on}."
            next
          end

          puts "  [PAYMENT ##{payment.id}] #{payment.amount.to_d.round(2)} #{payment.currency} -> #{converted_payment_amount.round(2)} USD (#{occurred_on})"

          unless dry_run
            payment.update_columns(
              amount_in_debt_currency: converted_payment_amount.round(2),
              exchange_rate_to_debt_currency: payment_rate,
              updated_at: Time.current
            )
          end

          payment_count += 1
        end
      end
    end

    if dry_run
      runner.call
    else
      Debt.transaction do
        runner.call

        if skipped_debts.any? || skipped_payments.any?
          raise ActiveRecord::Rollback,
                "Migracion cancelada: deudas omitidas=#{skipped_debts.size}, pagos omitidos=#{skipped_payments.size}."
        end
      end
    end

    puts '--- RESUMEN ---'
    puts "Deudas migradas: #{debt_count}"
    puts "Pagos recalculados: #{payment_count}"
    puts "Deudas omitidas: #{skipped_debts.size}#{skipped_debts.any? ? " (IDs: #{skipped_debts.join(', ')})" : ''}"
    puts "Pagos omitidos: #{skipped_payments.size}#{skipped_payments.any? ? " (IDs: #{skipped_payments.join(', ')})" : ''}"
    puts(dry_run ? 'DRY_RUN completado sin persistir cambios.' : 'Migracion completada y persistida.')
  end

  desc 'Normaliza base USD de deudas legacy por cobrar (convierte VES->USD y recalcula pagos historicos)'
  task normalize_legacy_usd_base: :environment do
    Rake::Task['debt:migrate_receivable_ves_to_usd'].reenable
    Rake::Task['debt:migrate_receivable_ves_to_usd'].invoke
  end

  desc 'Compatibilidad: ejecuta normalizacion legacy de deudas con base USD'
  task normalize_legacy_group_tokens: :environment do
    Rake::Task['debt:normalize_legacy_usd_base'].reenable
    Rake::Task['debt:normalize_legacy_usd_base'].invoke
  end
end
