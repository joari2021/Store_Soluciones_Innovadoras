class DashboardController < ApplicationController
  before_action :require_business
  before_action -> { require_module_access!(:ventas) }

  def index
    @from_date = parse_date(params[:from]) || 30.days.ago.to_date
    @to_date = parse_date(params[:to]) || Date.current
    if @from_date > @to_date
      @from_date, @to_date = @to_date, @from_date
    end

    range = @from_date.beginning_of_day..@to_date.end_of_day
    sales_scope = current_business.ventas.where(status: "paid", created_at: range).includes(:venta_items)

    @metrics = build_metrics(sales_scope)
    @monthly_rows = build_monthly_rows(sales_scope)
    @expense_rows = build_expense_rows(range)
    @passive_rows = build_passive_rows
  end

  private

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_notes_payload(raw_notes)
    return {} if raw_notes.blank?

    parsed = JSON.parse(raw_notes)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def to_decimal(value)
    value.to_d
  rescue StandardError
    0.to_d
  end

  def convert_to_usd(amount, currency, on_date)
    conversion = CurrencyConverter.convert(
      amount: amount.to_d,
      from_currency: currency,
      to_currency: "USD",
      on_date: on_date,
    )

    conversion&.dig(:amount).to_d
  end

  def build_metrics(sales_scope)
    totals = {
      product_revenue_usd: 0.to_d,
      product_cost_usd: 0.to_d,
      service_revenue_usd: 0.to_d,
      service_cost_usd: 0.to_d,
      sales_count: 0,
      sales_with_lot_cost_data: 0,
    }

    sales_scope.find_each do |sale|
      totals[:sales_count] += 1

      product_items = sale.venta_items.select { |row| row.producto_id.present? }
      service_items = sale.venta_items.select { |row| row.producto_id.blank? }

      totals[:product_revenue_usd] += product_items.sum { |row| row.subtotal_usd.to_d }
      totals[:service_revenue_usd] += service_items.sum { |row| row.subtotal_usd.to_d }

      notes = parse_notes_payload(sale.notes)

      lot_rows = Array(notes["product_lot_consumptions"]) 
      lot_cost = lot_rows.sum do |row|
        to_decimal(row["quantity"]) * to_decimal(row["unit_cost_usd"])
      end
      if lot_rows.any?
        totals[:sales_with_lot_cost_data] += 1
        totals[:product_cost_usd] += lot_cost
      end

      service_cost = Array(notes["service_cost_settlements"]).sum do |row|
        to_decimal(row["total_cost_usd"])
      end
      totals[:service_cost_usd] += service_cost
    end

    expense_paid_usd = ExpensePayment
      .joins(:expense)
      .where(expenses: { business_id: current_business.id })
      .where(occurred_at: @from_date.beginning_of_day..@to_date.end_of_day)
      .sum do |payment|
      convert_to_usd(payment.amount.to_d, payment.currency, payment.occurred_at)
    end

    gross_profit = (totals[:product_revenue_usd] - totals[:product_cost_usd]) +
      (totals[:service_revenue_usd] - totals[:service_cost_usd])

    {
      product_revenue_usd: totals[:product_revenue_usd].round(2),
      product_cost_usd: totals[:product_cost_usd].round(2),
      product_profit_usd: (totals[:product_revenue_usd] - totals[:product_cost_usd]).round(2),
      service_revenue_usd: totals[:service_revenue_usd].round(2),
      service_cost_usd: totals[:service_cost_usd].round(2),
      service_profit_usd: (totals[:service_revenue_usd] - totals[:service_cost_usd]).round(2),
      gross_profit_usd: gross_profit.round(2),
      expense_paid_usd: expense_paid_usd.round(2),
      net_profit_after_expenses_usd: (gross_profit - expense_paid_usd).round(2),
      sales_count: totals[:sales_count],
      sales_with_lot_cost_data: totals[:sales_with_lot_cost_data],
    }
  end

  def build_monthly_rows(sales_scope)
    monthly = Hash.new { |hash, key| hash[key] = { revenue: 0.to_d, cost: 0.to_d, profit: 0.to_d } }

    sales_scope.find_each do |sale|
      key = sale.created_at.in_time_zone("America/Caracas").beginning_of_month
      revenue = sale.total_usd.to_d

      notes = parse_notes_payload(sale.notes)
      product_cost = Array(notes["product_lot_consumptions"]).sum do |row|
        to_decimal(row["quantity"]) * to_decimal(row["unit_cost_usd"])
      end
      service_cost = Array(notes["service_cost_settlements"]).sum do |row|
        to_decimal(row["total_cost_usd"])
      end

      total_cost = (product_cost + service_cost).round(2)

      monthly[key][:revenue] += revenue
      monthly[key][:cost] += total_cost
      monthly[key][:profit] += (revenue - total_cost)
    end

    monthly.keys.sort.map do |month_start|
      row = monthly[month_start]
      {
        label: I18n.l(month_start.to_date, format: "%b %Y"),
        revenue: row[:revenue].round(2),
        cost: row[:cost].round(2),
        profit: row[:profit].round(2),
      }
    end
  end

  def build_expense_rows(range)
    payments = ExpensePayment
      .joins(:expense)
      .where(expenses: { business_id: current_business.id })
      .where(occurred_at: range)
      .includes(:expense)

    grouped = Hash.new(0.to_d)

    payments.each do |payment|
      label = payment.expense&.name.to_s.strip.presence || "Gasto"
      grouped[label] += convert_to_usd(payment.amount.to_d, payment.currency, payment.occurred_at)
    end

    grouped.sort_by { |_label, amount| -amount }.map do |label, amount|
      { label: label, amount_usd: amount.round(2) }
    end
  end

  def build_passive_rows
    payables = current_business.debts.where(debt_kind: "payable")

    grouped = Hash.new(0.to_d)

    payables.find_each do |debt|
      label = if debt.service_cost_record?
                "Costos de servicios pendientes"
              else
                "Cuentas por pagar"
              end
      grouped[label] += convert_to_usd(debt.balance.to_d, debt.currency, debt.issued_on)
    end

    grouped.sort_by { |_label, amount| -amount }.map do |label, amount|
      { label: label, amount_usd: amount.round(2) }
    end
  end
end
