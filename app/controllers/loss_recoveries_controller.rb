class LossRecoveriesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :load_setting

  def index
    @recent_entries = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc).limit(20)
    @summary = loss_recovery_summary
  end

  def history
    scope = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc)

    @from = parse_filter_date(params[:from])
    @to = parse_filter_date(params[:to])

    if @from.present?
      scope = scope.where("occurred_at >= ?", @from.in_time_zone.beginning_of_day)
    end

    if @to.present?
      scope = scope.where("occurred_at <= ?", @to.in_time_zone.end_of_day)
    end

    @entries = scope
    @summary = {
      total_excess_usd: @entries.sum(:excess_usd).to_d.round(2),
      total_excess_base: @entries.sum(:excess_base).to_d.round(2),
      count: @entries.count,
    }
  end

  def update_settings
    attrs = params.require(:loss_recovery_setting).permit(:active, :surcharge_percent, :min_invoice_total_usd)

    attrs[:surcharge_percent] = parse_decimal(attrs[:surcharge_percent]) if attrs.key?(:surcharge_percent)
    attrs[:min_invoice_total_usd] = parse_decimal(attrs[:min_invoice_total_usd]) if attrs.key?(:min_invoice_total_usd)

    @setting.assign_attributes(attrs)
    @setting.active = ActiveModel::Type::Boolean.new.cast(attrs[:active])

    if @setting.save
      redirect_to loss_recoveries_path, notice: "Configuracion de recuperacion actualizada."
    else
      @recent_entries = current_business.loss_recovery_entries.includes(:venta, :account).order(occurred_at: :desc).limit(20)
      @summary = loss_recovery_summary
      render :index, status: :unprocessable_entity
    end
  end

  private

  def load_setting
    @setting = current_business.loss_recovery_setting || current_business.build_loss_recovery_setting
  end

  def loss_recovery_summary
    entries = current_business.loss_recovery_entries
    {
      total_excess_usd: entries.sum(:excess_usd).to_d.round(2),
      total_excess_base: entries.sum(:excess_base).to_d.round(2),
      count: entries.count,
    }
  end

  def parse_filter_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_decimal(value)
    return 0.to_d if value.nil?
    return value.to_d if value.is_a?(Numeric)

    cleaned = value.to_s.strip.gsub(/[^\d,.-]/, "")
    if cleaned.include?(",") && cleaned.include?(".")
      cleaned = cleaned.gsub(".", "").tr(",", ".")
    elsif cleaned.include?(",")
      cleaned = cleaned.tr(",", ".")
    end

    BigDecimal(cleaned)
  rescue ArgumentError
    0.to_d
  end
end
