class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include Pagy::Backend

  before_action :set_tasas
  before_action :set_business_context
  before_action :set_header_notifications

  private

  def set_tasas
    return unless request.format.html? || request.format.turbo_stream?

    @latest_tasas = TasaCambio.latest_distinct_by_description.to_a
    tasas_by_description = @latest_tasas.index_by(&:description)

    dolar_bcv = tasas_by_description['Dolar BCV']
    euro_bcv = tasas_by_description['Euro BCV']
    unidad_vi = tasas_by_description['Unidad VI']

    @tasa_dolar_bcv = dolar_bcv&.valor || 'No disponible'
    @tasa_euro_bcv = euro_bcv&.valor || 'No disponible'
    @unidad_VI = unidad_vi&.valor || 'No disponible'
    @tasa_dolar_bcv_symbol = dolar_bcv&.symbol || '$'
    @tasa_euro_bcv_symbol = euro_bcv&.symbol || '€'
    @unidad_VI_symbol = unidad_vi&.symbol || 'Bs'
    @tasas = tasas_by_description.transform_values(&:valor)
  end

  def set_business_context
    return unless ActiveRecord::Base.connection.data_source_exists?('businesses')

    scoped_businesses = if Current.user&.admin?
                          Business.order(:name)
                        elsif Current.user.present?
                          Business.where(id: Current.user.business_id).order(:name)
                        else
                          Business.order(:name)
                        end

    @businesses = scoped_businesses.to_a

    @current_business = if session[:business_id].present?
                          @businesses.find { |business| business.id == session[:business_id].to_i }
                        end
    @current_business ||= @businesses.first

    if Current.user&.standard_staff? && Current.user&.business_id.present?
      @current_business = @businesses.find { |business| business.id == Current.user.business_id } || @current_business
    end

    session[:business_id] = @current_business&.id
    return unless Current.is_a?(Class) && Current.respond_to?(:business=)

    Current.business = @current_business
  end

  def set_header_notifications
    @header_notifications = []
    @header_notifications_count = 0
    return unless request.format.html? || request.format.turbo_stream?
    return unless Current.user.present?
    return if current_business.blank?

    user = Current.user
    can_view_admin_only_notifications = user.admin?
    can_view_low_stock_notification = user.admin? || user.manager? || user.standard_staff?

    if can_view_admin_only_notifications
      pending_pos_settlements_count = current_business
                                      .accounts
                                      .where(account_type: 'pos')
                                      .joins(:account_settlements)
                                      .where(account_settlements: { processed_at: nil })
                                      .count

      if pending_pos_settlements_count.positive?
        @header_notifications << {
          kind: 'pos_settlements',
          title: 'Cierres POS pendientes',
          summary: "Hay #{pending_pos_settlements_count} cierres de punto de venta pendientes por procesar.",
          href: accounts_path,
          count: pending_pos_settlements_count
        }
      end

      biopago_accounts = current_business.accounts.where(account_type: 'biopago')
      today_start_caracas = Time.current.in_time_zone('America/Caracas').beginning_of_day
      biopago_pending_closure_accounts_count = biopago_accounts.count do |account|
        account.account_movements.where(account_settlement_id: nil).where('occurred_at < ?', today_start_caracas).exists?
      end

      if biopago_pending_closure_accounts_count.positive?
        biopago_target_account = biopago_accounts.detect do |account|
          account.account_movements.where(account_settlement_id: nil).where('occurred_at < ?',
                                                                            today_start_caracas).exists?
        end

        @header_notifications << {
          kind: 'biopago_closures',
          title: 'Cierres Biopago pendientes',
          summary: "Hay #{biopago_pending_closure_accounts_count} cuentas Biopago con cierre diario pendiente.",
          href: biopago_target_account.present? ? account_path(biopago_target_account) : accounts_path,
          count: biopago_pending_closure_accounts_count
        }
      end
    end

    if can_view_low_stock_notification
      low_stock_product_ids = ProductVariation
                              .joins(:producto)
                              .where(productos: { business_id: current_business.id })
                              .where('COALESCE(product_variations.safety_stock, 0) > 0')
                              .left_joins(:stock_lot_variations)
                              .group('product_variations.id', 'product_variations.producto_id', 'product_variations.safety_stock')
                              .having('COALESCE(SUM(stock_lot_variations.quantity_remaining), 0) <= COALESCE(product_variations.safety_stock, 0)')
                              .pluck(Arel.sql('DISTINCT product_variations.producto_id'))

      if low_stock_product_ids.any?
        @header_notifications << {
          kind: 'low_stock',
          title: 'Stock bajo',
          summary: 'Hay productos con stock bajo.',
          href: productos_path(low_stock: 1),
          count: low_stock_product_ids.size
        }
      end
    end

    if can_view_admin_only_notifications
      below_target_margin_count = current_business
                                  .productos
                                  .includes(:profit_margin_preset, :stock_lots)
                                  .count(&:below_target_margin_for_highest_active_lot?)

      if below_target_margin_count.positive?
        @header_notifications << {
          kind: 'below_target_margin',
          title: 'Precio bajo objetivo',
          summary: 'Hay productos con precio por debajo del porcentaje fijado para el producto.',
          href: productos_path(below_target_margin: 1),
          count: below_target_margin_count
        }
      end
    end

    active_kinds = @header_notifications.map { |notification| notification[:kind].to_s }
    dismissed_kinds = dismissed_header_notification_kinds & active_kinds
    persist_dismissed_header_notification_kinds(dismissed_kinds)

    @header_notifications.reject! do |notification|
      dismissed_kinds.include?(notification[:kind].to_s)
    end

    @header_notifications_count = @header_notifications.size
  end

  def dismissed_header_notification_kinds
    dismiss_scope_key = header_notification_dismiss_scope_key
    return [] if dismiss_scope_key.blank?

    dismissed_store = session[:dismissed_header_notifications]
    return [] unless dismissed_store.is_a?(Hash)

    raw = dismissed_store[dismiss_scope_key] || dismissed_store[dismiss_scope_key.to_sym]
    Array(raw).map(&:to_s)
  end

  def persist_dismissed_header_notification_kinds(kinds)
    dismiss_scope_key = header_notification_dismiss_scope_key
    return if dismiss_scope_key.blank?

    session[:dismissed_header_notifications] ||= {}
    session[:dismissed_header_notifications][dismiss_scope_key] = Array(kinds).map(&:to_s).uniq
  end

  def header_notification_dismiss_scope_key
    user_id = Current.user&.id
    business_id = current_business&.id
    return nil if user_id.blank? || business_id.blank?

    "#{user_id}:#{business_id}"
  end

  attr_reader :current_business

  def current_user
    Current.user
  end

  def require_business
    return if current_business.present?

    redirect_to new_business_path, alert: 'Crea un negocio para continuar.'
  end
  helper_method :current_business, :current_user
end
