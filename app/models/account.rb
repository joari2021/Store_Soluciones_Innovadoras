class Account < ApplicationRecord
  belongs_to :business
  has_many :account_movements, -> { order(occurred_at: :desc, created_at: :desc) }, dependent: :destroy
  has_one_attached :logo
  has_one_attached :small_logo
  has_one_attached :payment_method_image

  ACCOUNT_TYPES = {
    'cash_box' => { label: 'Caja', icon: 'wallet' },
    'bank_account' => { label: 'Cuenta bancaria', icon: 'landmark' },
    'crypto_wallet' => { label: 'Billetera cripto', icon: 'bitcoin' },
    'card' => { label: 'Tarjeta', icon: 'credit-card' },
    'digital_wallet' => { label: 'Billetera digital', icon: 'smartphone' },
    'biopago' => { label: 'Biopago', icon: 'fingerprint' },
    'pos' => { label: 'Punto de venta', icon: 'credit-card' },
    'cashea' => { label: 'Cashea', icon: 'wallet' }
  }.freeze

  SPECIAL_ACCOUNT_TYPES = %w[biopago pos cashea].freeze
  SHARED_ACCOUNT_TYPES = (SPECIAL_ACCOUNT_TYPES + %w[cash_box]).freeze
  CASH_ROLES = {
    'cash_box' => 'Caja',
    'cash_deposit' => 'Deposito'
  }.freeze
  SETTLEMENT_REQUIRED_TYPES = %w[biopago pos].freeze
  SPECIAL_ACCOUNT_DEFAULTS = {
    'biopago' => { name: 'Biopago', currency: 'VES', theme_color: 'emerald' },
    'pos' => { name: 'Punto de venta', currency: 'VES', theme_color: 'sky' },
    'cashea' => { name: 'Cashea', currency: 'VES', theme_color: 'amber' }
  }.freeze
  has_many :account_settlements, dependent: :destroy
  belongs_to :settlement_account, class_name: 'Account', optional: true

  CURRENCIES = {
    'VES' => { label: 'Bolívares', symbol: 'Bs', icon: 'banknote' },
    'EUR' => { label: 'Euros', symbol: '€', icon: 'euro' },
    'USD' => { label: 'Dólares', symbol: '$', icon: 'dollar-sign' },
    'USDT' => { label: 'USDT', symbol: '₮', icon: 'circle-dollar-sign' },
    'BTC' => { label: 'Bitcoin', symbol: '₿', icon: 'bitcoin' },
    'BNB' => { label: 'BNB', symbol: 'BNB', icon: 'hexagon' }
  }.freeze

  COLOR_THEMES = {
    'sky' => {
      label: 'Azul cielo',
      card: 'border-sky-200 bg-sky-50',
      tag: 'bg-sky-100 text-sky-700',
      button: 'bg-sky-600 hover:bg-sky-700'
    },
    'emerald' => {
      label: 'Verde',
      card: 'border-emerald-200 bg-emerald-50',
      tag: 'bg-emerald-100 text-emerald-700',
      button: 'bg-emerald-600 hover:bg-emerald-700'
    },
    'violet' => {
      label: 'Violeta',
      card: 'border-violet-200 bg-violet-50',
      tag: 'bg-violet-100 text-violet-700',
      button: 'bg-violet-600 hover:bg-violet-700'
    },
    'amber' => {
      label: 'Ámbar',
      card: 'border-amber-200 bg-amber-50',
      tag: 'bg-amber-100 text-amber-700',
      button: 'bg-amber-600 hover:bg-amber-700'
    },
    'orange' => {
      label: 'Anaranjado',
      card: 'border-orange-200 bg-orange-50',
      tag: 'bg-orange-100 text-orange-700',
      button: 'bg-orange-600 hover:bg-orange-700'
    },
    'navy' => {
      label: 'Azul marino',
      card: 'border-blue-300 bg-blue-50',
      tag: 'bg-blue-900 text-blue-100',
      button: 'bg-blue-900 hover:bg-blue-950'
    },
    'rose' => {
      label: 'Rosa',
      card: 'border-rose-200 bg-rose-50',
      tag: 'bg-rose-100 text-rose-700',
      button: 'bg-rose-600 hover:bg-rose-700'
    },
    'slate' => {
      label: 'Slate',
      card: 'border-slate-300 bg-slate-100',
      tag: 'bg-slate-200 text-slate-700',
      button: 'bg-slate-700 hover:bg-slate-800'
    }
  }.freeze

  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES.keys }
  validates :currency, presence: true, inclusion: { in: CURRENCIES.keys }
  validates :theme_color, presence: true, inclusion: { in: COLOR_THEMES.keys }
  validates :balance, presence: true, numericality: true
  validates :shared_key, presence: true
  validates :cash_role, inclusion: { in: CASH_ROLES.keys }, allow_nil: true, if: :supports_cash_role?
  validate :primary_requires_bank_account
  validate :settlement_account_rules
  validate :settlement_currency_rules
  validate :validate_logo_attachment
  validate :validate_small_logo_attachment
  validate :validate_payment_method_image_attachment

  before_validation :ensure_shared_key
  before_validation :set_default_theme_color
  before_validation :clear_primary_for_non_bank
  before_validation :apply_special_defaults
  before_validation :normalize_cash_role, if: :supports_cash_role?
  before_save :unset_other_primary_bank_accounts, if: :will_save_change_to_is_primary?

  def self.account_type_options(include_special: false)
    types = include_special ? ACCOUNT_TYPES : ACCOUNT_TYPES.except(*SPECIAL_ACCOUNT_TYPES)
    types.map { |key, data| [data[:label], key] }
  end

  def self.currency_options
    CURRENCIES.map { |key, data| ["#{data[:label]} (#{data[:symbol]})", key] }
  end

  def self.theme_color_options
    COLOR_THEMES.map { |key, data| [data[:label], key] }
  end

  def self.ensure_special_accounts!(business)
    SPECIAL_ACCOUNT_DEFAULTS.each do |type, defaults|
      account = business.accounts.find_or_initialize_by(account_type: type)
      if account.persisted?
        account.update_columns(shared_key: SecureRandom.uuid, updated_at: Time.current) if account.shared_key.blank?
        next
      end

      account.name = defaults[:name]
      account.currency = defaults[:currency]
      account.theme_color = defaults[:theme_color]
      account.balance = 0
      account.active = false
      account.notes = 'Cuenta especial del sistema'
      account.save!
    end
  end

  def self.ensure_cash_accounts!(business)
    cash_definitions = [
      { name: 'Efectivo Bs (Caja)', currency: 'VES', cash_role: 'cash_box' },
      { name: 'Efectivo $ (Caja)', currency: 'USD', cash_role: 'cash_box' },
      { name: 'Efectivo Bs (Deposito)', currency: 'VES', cash_role: 'cash_deposit' },
      { name: 'Efectivo $ (Deposito)', currency: 'USD', cash_role: 'cash_deposit' }
    ]

    cash_definitions.each do |definition|
      account = business.accounts.find_or_initialize_by(
        account_type: 'cash_box',
        currency: definition[:currency],
        cash_role: definition[:cash_role]
      )
      next if account.persisted?

      account.name = definition[:name]
      account.theme_color = 'sky'
      account.balance = 0
      account.active = true
      account.notes = 'Cuenta de efectivo del sistema'
      account.save!
    end
  end

  def self.syncable_account_type?(account_type)
    SHARED_ACCOUNT_TYPES.include?(account_type.to_s)
  end

  def self.sync_shared_fields!(source_account)
    return if source_account.blank?
    return if source_account.shared_key.blank?
    return unless source_account.syncable_across_businesses?

    shared_attrs = {
      name: source_account.name,
      account_type: source_account.account_type,
      currency: source_account.currency,
      cash_role: source_account.cash_role,
      theme_color: source_account.theme_color,
      notes: source_account.notes
    }

    Business.find_each do |business|
      target = Account.find_by(business_id: business.id, shared_key: source_account.shared_key)

      if target.present?
        target.update_columns(shared_attrs.merge(updated_at: Time.current))
      else
        target = business.accounts.create!(
          shared_key: source_account.shared_key,
          balance: 0,
          active: false,
          is_primary: false,
          **shared_attrs
        )
      end

      source_account.sync_shared_attachments!(target) if target.id != source_account.id
    end
  end

  def self.seed_from_master!(master_business, target_business)
    return if master_business.blank? || target_business.blank?

    master_business.accounts.order(:id).find_each do |master_account|
      next unless master_account.syncable_across_businesses?

      target = target_business.accounts.find_by(shared_key: master_account.shared_key)

      if target.blank?
        target = target_business.accounts.find_by(
          name: master_account.name,
          account_type: master_account.account_type,
          currency: master_account.currency
        )
      end

      if target.present?
        target.update_columns(
          shared_key: master_account.shared_key,
          name: master_account.name,
          account_type: master_account.account_type,
          currency: master_account.currency,
          cash_role: master_account.cash_role,
          theme_color: master_account.theme_color,
          notes: master_account.notes,
          updated_at: Time.current
        )
      else
        target = target_business.accounts.create!(
          shared_key: master_account.shared_key,
          name: master_account.name,
          account_type: master_account.account_type,
          currency: master_account.currency,
          cash_role: master_account.cash_role,
          theme_color: master_account.theme_color,
          notes: master_account.notes,
          balance: 0,
          active: false,
          is_primary: false
        )
      end

      master_account.sync_shared_attachments!(target)
    end
  end

  def account_type_label
    ACCOUNT_TYPES.dig(account_type, :label) || account_type.to_s.humanize
  end

  def account_type_icon
    ACCOUNT_TYPES.dig(account_type, :icon) || 'wallet'
  end

  def currency_label
    CURRENCIES.dig(currency, :label) || currency.to_s.upcase
  end

  def currency_symbol
    CURRENCIES.dig(currency, :symbol) || currency.to_s.upcase
  end

  def currency_icon
    CURRENCIES.dig(currency, :icon) || 'coins'
  end

  def theme_config
    COLOR_THEMES[theme_color] || COLOR_THEMES['sky']
  end

  def settlement_enabled?
    SPECIAL_ACCOUNT_TYPES.include?(account_type)
  end

  def cash_box_account?
    account_type == 'cash_box'
  end

  def cash_box_role?
    supports_cash_role? && cash_box_account? && cash_role == 'cash_box'
  end

  def cash_deposit_role?
    supports_cash_role? && cash_box_account? && cash_role == 'cash_deposit'
  end

  def syncable_across_businesses?
    self.class.syncable_account_type?(account_type)
  end

  def insufficient_balance_message(required_amount, available_balance: balance)
    required = required_amount.to_d.round(2)
    available = available_balance.to_d.round(2)
    missing = [required - available, 0.to_d].max.round(2)

    "Saldo insuficiente en la cuenta #{name}. " \
      "Saldo actual: #{format_currency_amount(available)}. " \
      "Monto a debitar: #{format_currency_amount(required)}. " \
      "Faltan: #{format_currency_amount(missing)}."
  end

  def settlement_account_required?
    SETTLEMENT_REQUIRED_TYPES.include?(account_type)
  end

  def recalculate_balance!
    movements_scope = account_movements
    movements_scope = movements_scope.where(account_settlement_id: nil) if settlement_enabled?

    signed_total = movements_scope.sum(
      Arel.sql("CASE WHEN movement_kind = 'expense' THEN -amount ELSE amount END")
    )

    update_columns(balance: signed_total, updated_at: Time.current)
  end

  def sync_shared_attachments!(target)
    sync_attachment(:logo, target)
    sync_attachment(:small_logo, target)
    sync_attachment(:payment_method_image, target)
  end

  private

  def ensure_shared_key
    self.shared_key = SecureRandom.uuid if shared_key.blank?
  end

  def set_default_theme_color
    self.theme_color = 'sky' if theme_color.blank?
  end

  def apply_special_defaults
    return unless settlement_enabled?

    self.currency = 'VES'
    defaults = SPECIAL_ACCOUNT_DEFAULTS[account_type]
    self.name = defaults[:name] if name.blank? && defaults
    self.theme_color = defaults[:theme_color] if theme_color.blank? && defaults
  end

  def clear_primary_for_non_bank
    self.is_primary = false unless account_type == 'bank_account'
  end

  def normalize_cash_role
    if cash_box_account?
      self.cash_role = infer_cash_role_from_name if cash_role.blank?
    else
      self.cash_role = nil
    end
  end

  def supports_cash_role?
    self.class.column_names.include?('cash_role')
  end

  def infer_cash_role_from_name
    name.to_s.downcase.include?('deposito') ? 'cash_deposit' : 'cash_box'
  end

  def unset_other_primary_bank_accounts
    return unless is_primary

    Account.where(business_id: business_id, account_type: 'bank_account')
           .where.not(id: id)
           .update_all(is_primary: false, updated_at: Time.current)
  end

  def primary_requires_bank_account
    return unless is_primary
    return if account_type == 'bank_account'

    errors.add(:is_primary, 'solo aplica a cuentas bancarias')
  end

  def settlement_account_rules
    return unless settlement_enabled?
    return unless active?

    if settlement_account_required? && settlement_account.blank?
      errors.add(:settlement_account_id, 'es requerido para activar esta cuenta')
      return
    end

    return if settlement_account.blank?

    if settlement_account.business_id != business_id
      errors.add(:settlement_account_id, 'debe pertenecer al mismo negocio')
      return
    end

    return if settlement_account.account_type == 'bank_account' && settlement_account.currency == 'VES'

    errors.add(:settlement_account_id, 'debe ser una cuenta bancaria en Bs')
  end

  def settlement_currency_rules
    return unless settlement_enabled?
    return if currency == 'VES'

    errors.add(:currency, 'debe ser Bs para esta cuenta')
  end

  def validate_logo_attachment
    validate_image_attachment(:logo)
  end

  def validate_small_logo_attachment
    validate_image_attachment(:small_logo)
  end

  def validate_payment_method_image_attachment
    validate_image_attachment(:payment_method_image)
  end

  def validate_image_attachment(attribute)
    attachment = public_send(attribute)
    return unless attachment.attached?

    unless attachment.blob.content_type.in?(%w[image/png image/jpeg image/jpg image/webp image/svg+xml image/gif])
      errors.add(attribute, 'debe ser una imagen valida (PNG, JPG, WEBP, SVG o GIF).')
    end

    return unless attachment.blob.byte_size > 5.megabytes

    errors.add(attribute, 'debe pesar menos de 5MB.')
  end

  def sync_attachment(attribute, target)
    source_attachment = public_send(attribute)
    target_attachment = target.public_send(attribute)

    if source_attachment.attached?
      return if target_attachment.attached? && target_attachment.blob_id == source_attachment.blob_id

      target_attachment.attach(source_attachment.blob)
      return
    end

    target_attachment.purge_later if target_attachment.attached?
  end

  def format_currency_amount(value)
    ApplicationController.helpers.number_to_currency(value.to_d.round(2), unit: "#{currency_symbol} ")
  end
end
