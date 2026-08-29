namespace :debts do
  desc "Recupera pagos de deudas faltantes a partir de AccountMovement [DP:x] [DEBT:y] (dry-run por defecto)"
  task recover_missing_transferred_payments: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])
    business_id_filter = ENV["BUSINESS_ID"].to_i
    business_id_filter = nil unless business_id_filter.positive?

    puts "== Recuperacion de pagos faltantes por transferencias =="
    puts "Modo: #{apply ? 'APLICAR CAMBIOS' : 'DRY-RUN (sin escribir)'}"
    puts "Filtro business_id: #{business_id_filter || 'ninguno'}"

    movement_scope = AccountMovement
                     .includes(:account)
                     .where("description LIKE ?", "%[DP:%")
                     .where("description LIKE ?", "%[DEBT:%")
                     .order(:id)

    stats = {
      scanned: 0,
      candidate_missing: 0,
      already_present: 0,
      already_recovered: 0,
      skipped_missing_debt: 0,
      skipped_missing_account: 0,
      skipped_business_filter: 0,
      recovered: 0,
      failed: 0,
    }

    failed_rows = []

    select_target_account = lambda do |business:, preferred_currency:|
      normalized_currency = preferred_currency.to_s.upcase
      base_scope = business.accounts.where.not(account_type: 'cashea')

      base_scope.where(account_type: 'cash_box', currency: normalized_currency, active: true).order(:id).first ||
        base_scope.where(account_type: 'cash_box', currency: normalized_currency).order(:id).first ||
        base_scope.where(account_type: 'cash_box', active: true).order(:id).first ||
        base_scope.where(account_type: 'cash_box').order(:id).first ||
        base_scope.where(currency: normalized_currency, active: true).order(:id).first ||
        base_scope.where(currency: normalized_currency).order(:id).first ||
        base_scope.where(active: true).order(:id).first ||
        base_scope.order(:id).first
    end

    recovery_note_for_dp = lambda do |dp_id|
      "%[RECOVERED_FROM_DP:#{dp_id}]%"
    end

    movement_scope.find_each do |movement|
      stats[:scanned] += 1

      description = movement.description.to_s
      dp_id = description[/\[DP:(\d+)\]/, 1].to_i
      debt_id = description[/\[DEBT:(\d+)\]/, 1].to_i
      next unless dp_id.positive? && debt_id.positive?

      if DebtPayment.exists?(id: dp_id)
        stats[:already_present] += 1
        next
      end

      if DebtPayment.where("notes LIKE ?", recovery_note_for_dp.call(dp_id)).exists?
        stats[:already_recovered] += 1
        next
      end

      stats[:candidate_missing] += 1

      debt = Debt.find_by(id: debt_id)
      if debt.blank?
        stats[:skipped_missing_debt] += 1
        next
      end

      if business_id_filter.present? && debt.business_id != business_id_filter
        stats[:skipped_business_filter] += 1
        next
      end

      preferred_currency = movement.account&.currency.to_s.upcase.presence || debt.currency.to_s.upcase
      target_account = select_target_account.call(
        business: debt.business,
        preferred_currency: preferred_currency,
      )

      if target_account.blank?
        stats[:skipped_missing_account] += 1
        failed_rows << {
          movement_id: movement.id,
          debt_id: debt.id,
          dp_id: dp_id,
          reason: 'No hay cuenta destino disponible en el negocio de la deuda',
        }
        next
      end

      notes = [
        "[RECOVERED_FROM_DP:#{dp_id}]",
        "[RECOVERED_FROM_AM:#{movement.id}]",
        "[MIRROR_SYNC]",
      ].join(' ')

      attrs = {
        debt_id: debt.id,
        account_id: target_account.id,
        amount: movement.amount.to_d,
        occurred_at: movement.occurred_at&.to_date || Date.current,
        notes: notes,
      }

      if apply
        payment = DebtPayment.new(attrs)
        payment.skip_account_movement = true
        payment.save!
      end

      stats[:recovered] += 1
    rescue StandardError => e
      stats[:failed] += 1
      failed_rows << {
        movement_id: movement.id,
        debt_id: debt_id,
        dp_id: dp_id,
        reason: e.message,
      }
    end

    puts "\n== Resumen =="
    stats.each do |key, value|
      puts "#{key}: #{value}"
    end

    if failed_rows.any?
      puts "\n== Fallos / saltados relevantes (max 100) =="
      failed_rows.first(100).each do |row|
        puts "movement_id=#{row[:movement_id]} debt_id=#{row[:debt_id]} dp_id=#{row[:dp_id]} :: #{row[:reason]}"
      end
    end

    puts "\nFinalizado."
  end

  desc "Audita grupos transferidos y detecta posibles faltantes de cobros (solo lectura)"
  task audit_transferred_groups: :environment do
    business_id_filter = ENV["BUSINESS_ID"].to_i
    business_id_filter = nil unless business_id_filter.positive?
    min_delta = ENV["MIN_DELTA"].to_d
    min_delta = 0.01.to_d if min_delta <= 0

    puts "== Auditoria de grupos transferidos =="
    puts "Filtro business_id: #{business_id_filter || 'ninguno'}"
    puts "Delta minimo reportado: #{min_delta.to_s('F')}"

    scope = Debt.where("description LIKE ? OR description LIKE ?", "%[TRANSFER_FROM_BUSINESS:%", "%[IC_MIRROR]%")
    scope = scope.where(business_id: business_id_filter) if business_id_filter.present?

    debts = scope.includes(:debt_payments).to_a
    if debts.empty?
      puts "No se encontraron deudas marcadas como transferidas en el alcance indicado."
      next
    end

    grouped = debts.group_by do |debt|
      token = debt.group_token.to_s.strip
      token = "legacy-#{debt.group_root_debt_id}" if token.blank? && debt.group_root_debt_id.present?
      token = "debt-#{debt.id}" if token.blank?
      [debt.business_id, debt.debt_kind, token, debt.currency.to_s.upcase, debt.cliente_id, debt.acreedor.to_s.strip.downcase]
    end

    rows = []
    grouped.each do |key, group_debts|
      business_id, debt_kind, token, currency, cliente_id, acreedor_key = key
      total_amount = group_debts.sum { |d| d.amount.to_d }.round(2)
      total_paid = group_debts.sum { |d| d.debt_payments.to_a.sum { |p| p.amount_in_debt_currency.to_d } }.round(2)
      total_balance = (total_amount - total_paid).round(2)

      transfer_notes_count = group_debts.sum do |d|
        d.debt_payments.to_a.count { |p| p.notes.to_s.include?("[TRANSFER_FROM_BUSINESS:") }
      end

      rows << {
        business_id: business_id,
        debt_kind: debt_kind,
        group_token: token,
        currency: currency,
        cliente_id: cliente_id,
        acreedor_key: acreedor_key,
        debts_count: group_debts.size,
        amount_total: total_amount,
        paid_total: total_paid,
        balance_total: total_balance,
        transfer_payments_marked: transfer_notes_count,
      }
    end

    suspicious = rows.select do |row|
      row[:balance_total] > min_delta && row[:transfer_payments_marked].zero?
    end

    puts "Grupos analizados: #{rows.size}"
    puts "Grupos sospechosos (saldo > #{min_delta.to_s('F')} y sin pagos marcados de transferencia): #{suspicious.size}"

    suspicious.first(200).each do |row|
      puts [
        "business_id=#{row[:business_id]}",
        "kind=#{row[:debt_kind]}",
        "token=#{row[:group_token]}",
        "currency=#{row[:currency]}",
        "debts=#{row[:debts_count]}",
        "amount=#{row[:amount_total].to_s('F')}",
        "paid=#{row[:paid_total].to_s('F')}",
        "balance=#{row[:balance_total].to_s('F')}",
        "transfer_payments_marked=#{row[:transfer_payments_marked]}",
      ].join(" | ")
    end

    puts "\nFinalizado."
  end

  desc "Recupera cobros faltantes para un cliente transferido usando movimientos del negocio origen (dry-run por defecto)"
  task recover_transferred_client_payments: :environment do
    source_business_id = ENV["SOURCE_BUSINESS_ID"].to_i
    destination_business_id = ENV["DESTINATION_BUSINESS_ID"].to_i
    destination_cliente_id = ENV["DESTINATION_CLIENTE_ID"].to_i
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])

    unless source_business_id.positive? && destination_business_id.positive? && destination_cliente_id.positive?
      puts "Debes enviar SOURCE_BUSINESS_ID, DESTINATION_BUSINESS_ID y DESTINATION_CLIENTE_ID."
      next
    end

    source_business = Business.find_by(id: source_business_id)
    destination_business = Business.find_by(id: destination_business_id)

    if source_business.blank? || destination_business.blank?
      puts "No se encontraron los negocios indicados."
      next
    end

    puts "== Reparacion por cliente transferido =="
    puts "source_business_id=#{source_business_id} destination_business_id=#{destination_business_id} destination_cliente_id=#{destination_cliente_id}"
    puts "Modo: #{apply ? 'APLICAR CAMBIOS' : 'DRY-RUN (sin escribir)'}"

    destination_debts = destination_business
                        .debts
                        .excluding_service_cost_records
                        .where(debt_kind: 'receivable', cliente_id: destination_cliente_id)
                        .includes(:debt_payments)

    debt_ids = destination_debts.map(&:id)
    if debt_ids.empty?
      puts "No hay deudas por cobrar del cliente destino en el negocio destino."
      next
    end

    select_target_account = lambda do |business:, preferred_currency:|
      normalized_currency = preferred_currency.to_s.upcase
      base_scope = business.accounts.where.not(account_type: 'cashea')

      base_scope.where(account_type: 'cash_box', currency: normalized_currency, active: true).order(:id).first ||
        base_scope.where(account_type: 'cash_box', currency: normalized_currency).order(:id).first ||
        base_scope.where(account_type: 'cash_box', active: true).order(:id).first ||
        base_scope.where(account_type: 'cash_box').order(:id).first ||
        base_scope.where(currency: normalized_currency, active: true).order(:id).first ||
        base_scope.where(currency: normalized_currency).order(:id).first ||
        base_scope.where(active: true).order(:id).first ||
        base_scope.order(:id).first
    end

    source_movements = AccountMovement
                       .joins(:account)
                       .includes(:account)
                       .where(accounts: { business_id: source_business.id })
                       .where(movement_kind: 'income')
                       .where("description LIKE ?", "%[DEBT:%")
                       .where("description LIKE ?", "%[DP:%")

    stats = {
      scanned_movements: 0,
      matching_movements: 0,
      candidate_missing: 0,
      already_present: 0,
      already_recovered: 0,
      skipped_no_target_account: 0,
      recovered: 0,
      failed: 0,
    }

    details = []

    source_movements.find_each do |movement|
      stats[:scanned_movements] += 1
      description = movement.description.to_s
      debt_id = description[/\[DEBT:(\d+)\]/, 1].to_i
      dp_id = description[/\[DP:(\d+)\]/, 1].to_i
      next unless debt_id.positive? && dp_id.positive?
      next unless debt_ids.include?(debt_id)

      stats[:matching_movements] += 1

      if DebtPayment.exists?(id: dp_id)
        stats[:already_present] += 1
        next
      end

      recovery_note_pattern = "%[RECOVERED_FROM_AM:#{movement.id}]%"
      if DebtPayment.where("notes LIKE ?", recovery_note_pattern).exists?
        stats[:already_recovered] += 1
        next
      end

      stats[:candidate_missing] += 1

      debt = destination_debts.find { |d| d.id == debt_id }
      preferred_currency = movement.account&.currency.to_s.upcase.presence || debt.currency.to_s.upcase
      target_account = select_target_account.call(business: destination_business, preferred_currency: preferred_currency)

      if target_account.blank?
        stats[:skipped_no_target_account] += 1
        details << {
          movement_id: movement.id,
          debt_id: debt_id,
          dp_id: dp_id,
          status: 'skipped_no_target_account',
        }
        next
      end

      attrs = {
        debt_id: debt.id,
        account_id: target_account.id,
        amount: movement.amount.to_d,
        occurred_at: movement.occurred_at&.to_date || Date.current,
        notes: [
          "[TRANSFER_REPAIR]",
          "[RECOVERED_FROM_SOURCE_BUSINESS:#{source_business.id}]",
          "[RECOVERED_FROM_AM:#{movement.id}]",
          "[RECOVERED_FROM_DP:#{dp_id}]",
          "[MIRROR_SYNC]",
        ].join(' '),
      }

      if apply
        payment = DebtPayment.new(attrs)
        payment.skip_account_movement = true
        payment.save!
      end

      stats[:recovered] += 1
      details << {
        movement_id: movement.id,
        debt_id: debt.id,
        dp_id: dp_id,
        amount: movement.amount.to_d.round(2).to_s('F'),
        movement_currency: movement.account&.currency,
        target_account_id: target_account.id,
        target_account_currency: target_account.currency,
        status: apply ? 'recovered' : 'candidate',
      }
    rescue StandardError => e
      stats[:failed] += 1
      details << {
        movement_id: movement.id,
        debt_id: debt_id,
        dp_id: dp_id,
        status: 'failed',
        error: e.message,
      }
    end

    puts "\n== Resumen =="
    stats.each { |k, v| puts "#{k}: #{v}" }

    puts "\n== Detalle (max 200) =="
    details.first(200).each do |row|
      puts row.map { |k, v| "#{k}=#{v}" }.join(' | ')
    end

    puts "\nFinalizado."
  end
end
