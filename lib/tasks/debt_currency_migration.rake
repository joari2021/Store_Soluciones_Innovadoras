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

  desc 'Normaliza deudas legacy por base USD unificando group_token sin convertir montos ni monedas'
  task normalize_legacy_group_tokens: :environment do
    business_id = ENV['BUSINESS_ID'].presence
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))

    scope = Debt
            .excluding_service_cost_records
            .where(debt_kind: 'receivable')
            .order(:business_id, :cliente_id, :issued_on, :created_at, :id)

    scope = scope.where(business_id: business_id.to_i) if business_id.present?

    puts "Iniciando normalizacion legacy por base USD (solo group_token). BUSINESS_ID=#{business_id || 'ALL'} DRY_RUN=#{dry_run}"

    debts = scope.to_a
    grouped = debts.group_by do |debt|
      [
        debt.business_id,
        debt.cliente_id,
        debt.debt_kind,
        legacy_base_currency_for_grouping(debt.currency)
      ]
    end

    updated_count = 0
    affected_groups = 0

    runner = lambda do
      grouped.each do |(group_business_id, group_cliente_id, group_kind, group_base_currency), group_debts|
        next if group_debts.size <= 1

        canonical_token = canonical_group_token_for(group_debts)
        changed_in_group = 0

        group_debts.each do |debt|
          current_token = debt.group_token.to_s.strip
          next if current_token == canonical_token

          changed_in_group += 1
          updated_count += 1

          next if dry_run

          debt.update_columns(group_token: canonical_token, updated_at: Time.current)
        end

        next if changed_in_group.zero?

        affected_groups += 1
        puts "[GROUP] business=#{group_business_id} cliente=#{group_cliente_id || 'NONE'} kind=#{group_kind} base=#{group_base_currency} size=#{group_debts.size} updates=#{changed_in_group} token=#{canonical_token}"
      end
    end

    if dry_run
      runner.call
    else
      Debt.transaction { runner.call }
    end

    puts '--- RESUMEN ---'
    puts "Grupos afectados: #{affected_groups}"
    puts "Deudas actualizadas: #{updated_count}"
    puts(dry_run ? 'DRY_RUN completado sin persistir cambios.' : 'Normalizacion completada y persistida.')
  end

  desc 'Alias: normaliza base USD legacy unificando group_token (sin conversion de montos)'
  task normalize_legacy_usd_base: :environment do
    Rake::Task['debt:normalize_legacy_group_tokens'].reenable
    Rake::Task['debt:normalize_legacy_group_tokens'].invoke
  end

  def legacy_base_currency_for_grouping(currency)
    normalized = currency.to_s.strip.upcase
    return 'USD' if %w[USD VES].include?(normalized)

    normalized
  end

  def canonical_group_token_for(group_debts)
    token_source = group_debts
                   .select { |debt| debt.group_token.to_s.strip.present? }
                   .max_by do |debt|
                     [debt.issued_on || debt.created_at&.to_date || Date.new(1970, 1, 1), debt.created_at || Time.zone.at(0),
                      debt.id.to_i]
                   end

    token_source&.group_token.to_s.strip.presence || "grp_legacy_#{SecureRandom.hex(8)}"
  end
end
