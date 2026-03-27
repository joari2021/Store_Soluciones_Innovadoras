class Business < ApplicationRecord
  DEFAULT_THEME_PROFILE = 'neon_blue'.freeze
  THEME_PROFILES = {
    'neon_blue' => {
      label: 'Azul claro + cyan',
      description: 'Azules claros y cyan electrico para una interfaz luminosa y limpia.',
      preview: {
        background: 'radial-gradient(circle at 16% 18%, rgba(56, 189, 248, 0.28) 0%, rgba(56, 189, 248, 0) 40%), radial-gradient(circle at 82% 12%, rgba(34, 211, 238, 0.30) 0%, rgba(34, 211, 238, 0) 36%), linear-gradient(135deg, #eefbff 0%, #d7f4ff 50%, #b3ecff 100%)',
        ring: 'rgba(56, 189, 248, 0.32)',
        glow: 'rgba(14, 165, 233, 0.28)',
        text: '#0e7490',
        badge_background: 'rgba(255, 255, 255, 0.72)',
        badge_text: '#0369a1'
      },
      css: {
        'theme-shell-bg-start' => '#eefbff',
        'theme-shell-bg-mid' => '#dcf6ff',
        'theme-shell-bg-end' => '#c8eeff',
        'theme-shell-glow-1' => 'rgba(14, 165, 233, 0.18)',
        'theme-shell-glow-2' => 'rgba(34, 211, 238, 0.20)',
        'theme-selection-bg' => '#67e8f9',
        'theme-selection-text' => '#0c4a6e',
        'theme-glass-bg' => 'rgba(255, 255, 255, 0.78)',
        'theme-glass-border' => 'rgba(125, 211, 252, 0.34)',
        'theme-card-border' => 'rgba(103, 232, 249, 0.34)',
        'theme-nav-active-bg' => 'rgba(14, 165, 233, 0.24)',
        'theme-nav-active-text' => '#075985',
        'theme-nav-hover-bg' => 'rgba(14, 165, 233, 0.18)',
        'theme-nav-hover-text' => '#0369a1',
        'theme-nav-logo-start' => '#38bdf8',
        'theme-nav-logo-end' => '#22d3ee',
        'theme-nav-logo-shadow' => 'rgba(34, 211, 238, 0.34)',
        'theme-surface-hero-border' => 'rgba(103, 232, 249, 0.52)',
        'theme-surface-hero-from' => '#f3fdff',
        'theme-surface-hero-via' => '#e6f9ff',
        'theme-surface-hero-to' => '#c8f2ff',
        'theme-surface-hero-kicker-bg' => 'rgba(255, 255, 255, 0.86)',
        'theme-surface-hero-kicker-border' => 'rgba(125, 211, 252, 0.52)',
        'theme-surface-hero-kicker-text' => '#0369a1',
        'theme-surface-hero-heading' => '#0369a1',
        'theme-surface-hero-body' => '#0e7490',
        'theme-surface-hero-orb-primary' => 'rgba(34, 211, 238, 0.24)',
        'theme-surface-hero-orb-secondary' => 'rgba(56, 189, 248, 0.22)',
        'theme-surface-panel-border' => 'rgba(125, 211, 252, 0.52)',
        'theme-surface-panel-from' => '#e4f8ff',
        'theme-surface-panel-via' => '#ccf1ff',
        'theme-surface-panel-to' => '#9be6ff',
        'theme-surface-panel-heading' => '#075985',
        'theme-surface-panel-body' => 'rgba(14, 116, 144, 0.86)',
        'theme-surface-panel-icon' => '#0891b2',
        'theme-surface-summary-border' => 'rgba(125, 211, 252, 0.52)',
        'theme-surface-summary-from' => '#f0fdff',
        'theme-surface-summary-via' => '#e4f8ff',
        'theme-surface-summary-to' => '#cbf0ff',
        'theme-surface-summary-total' => '#0369a1',
        'theme-pay-button-from' => '#0ea5e9',
        'theme-pay-button-to' => '#06b6d4',
        'theme-pay-button-shadow' => 'rgba(14, 165, 233, 0.28)',
        'theme-pay-button-hover-from' => '#38bdf8',
        'theme-pay-button-hover-to' => '#22d3ee',
        'theme-sky-50' => '#f0fdff',
        'theme-sky-100' => '#dff7ff',
        'theme-sky-200' => '#bae9ff',
        'theme-sky-300' => '#7ddcff',
        'theme-sky-500' => '#0ea5e9',
        'theme-sky-600' => '#0284c7',
        'theme-sky-700' => '#0369a1',
        'theme-sky-800' => '#075985',
        'theme-sky-900' => '#0c4a6e',
        'theme-cyan-50' => '#ecfeff',
        'theme-cyan-100' => '#cffafe',
        'theme-cyan-200' => '#a5f3fc',
        'theme-cyan-400' => '#22d3ee',
        'theme-cyan-500' => '#06b6d4',
        'theme-cyan-600' => '#0891b2',
        'theme-cyan-700' => '#0e7490',
        'theme-input-border' => '#38bdf8',
        'theme-input-focus' => '#06b6d4',
        'theme-input-shadow' => 'rgba(34, 211, 238, 0.26)',
        'theme-focus-ring' => 'rgba(56, 189, 248, 0.20)',
        'theme-accent-shadow' => 'rgba(34, 211, 238, 0.30)'
      }
    },
    'electric_cyan' => {
      label: 'Cyan electrico',
      description: 'Cyan electrico y azules claros con brillo alto para destacar acciones.',
      preview: {
        background: 'radial-gradient(circle at 20% 20%, rgba(34, 211, 238, 0.36) 0%, rgba(34, 211, 238, 0) 38%), radial-gradient(circle at 82% 12%, rgba(56, 189, 248, 0.32) 0%, rgba(56, 189, 248, 0) 34%), linear-gradient(135deg, #f2feff 0%, #d9fbff 52%, #b4f3ff 100%)',
        ring: 'rgba(34, 211, 238, 0.36)',
        glow: 'rgba(6, 182, 212, 0.34)',
        text: '#0e7490',
        badge_background: 'rgba(255, 255, 255, 0.74)',
        badge_text: '#0e7490'
      },
      css: {
        'theme-shell-bg-start' => '#f2feff',
        'theme-shell-bg-mid' => '#dafcff',
        'theme-shell-bg-end' => '#baf7ff',
        'theme-shell-glow-1' => 'rgba(6, 182, 212, 0.24)',
        'theme-shell-glow-2' => 'rgba(14, 165, 233, 0.22)',
        'theme-selection-bg' => '#22d3ee',
        'theme-selection-text' => '#083344',
        'theme-glass-bg' => 'rgba(255, 255, 255, 0.80)',
        'theme-glass-border' => 'rgba(45, 212, 191, 0.32)',
        'theme-card-border' => 'rgba(103, 232, 249, 0.36)',
        'theme-nav-active-bg' => 'rgba(6, 182, 212, 0.24)',
        'theme-nav-active-text' => '#0f766e',
        'theme-nav-hover-bg' => 'rgba(6, 182, 212, 0.18)',
        'theme-nav-hover-text' => '#0d9488',
        'theme-nav-logo-start' => '#06b6d4',
        'theme-nav-logo-end' => '#00d4ff',
        'theme-nav-logo-shadow' => 'rgba(6, 182, 212, 0.34)',
        'theme-surface-hero-border' => 'rgba(45, 212, 191, 0.50)',
        'theme-surface-hero-from' => '#f4ffff',
        'theme-surface-hero-via' => '#d9fbff',
        'theme-surface-hero-to' => '#baf6ff',
        'theme-surface-hero-kicker-bg' => 'rgba(255, 255, 255, 0.86)',
        'theme-surface-hero-kicker-border' => 'rgba(34, 211, 238, 0.44)',
        'theme-surface-hero-kicker-text' => '#0e7490',
        'theme-surface-hero-heading' => '#0e7490',
        'theme-surface-hero-body' => '#0f766e',
        'theme-surface-hero-orb-primary' => 'rgba(6, 182, 212, 0.26)',
        'theme-surface-hero-orb-secondary' => 'rgba(34, 211, 238, 0.24)',
        'theme-surface-panel-border' => 'rgba(45, 212, 191, 0.48)',
        'theme-surface-panel-from' => '#defcff',
        'theme-surface-panel-via' => '#b5f6ff',
        'theme-surface-panel-to' => '#7eefff',
        'theme-surface-panel-heading' => '#0e7490',
        'theme-surface-panel-body' => 'rgba(8, 145, 178, 0.86)',
        'theme-surface-panel-icon' => '#06b6d4',
        'theme-surface-summary-border' => 'rgba(45, 212, 191, 0.48)',
        'theme-surface-summary-from' => '#edffff',
        'theme-surface-summary-via' => '#d5faff',
        'theme-surface-summary-to' => '#b7f5ff',
        'theme-surface-summary-total' => '#0e7490',
        'theme-pay-button-from' => '#06b6d4',
        'theme-pay-button-to' => '#00d4ff',
        'theme-pay-button-shadow' => 'rgba(6, 182, 212, 0.30)',
        'theme-pay-button-hover-from' => '#22d3ee',
        'theme-pay-button-hover-to' => '#38bdf8',
        'theme-sky-50' => '#effcff',
        'theme-sky-100' => '#d5f8ff',
        'theme-sky-200' => '#aeefff',
        'theme-sky-300' => '#7de4ff',
        'theme-sky-500' => '#00b8ff',
        'theme-sky-600' => '#0ea5e9',
        'theme-sky-700' => '#0284c7',
        'theme-sky-800' => '#0369a1',
        'theme-sky-900' => '#075985',
        'theme-cyan-50' => '#ecfeff',
        'theme-cyan-100' => '#ccfbf1',
        'theme-cyan-200' => '#99f6e4',
        'theme-cyan-400' => '#2dd4bf',
        'theme-cyan-500' => '#14b8a6',
        'theme-cyan-600' => '#0d9488',
        'theme-cyan-700' => '#0f766e',
        'theme-input-border' => '#22d3ee',
        'theme-input-focus' => '#00d4ff',
        'theme-input-shadow' => 'rgba(6, 182, 212, 0.30)',
        'theme-focus-ring' => 'rgba(6, 182, 212, 0.24)',
        'theme-accent-shadow' => 'rgba(34, 211, 238, 0.34)'
      }
    },
    'neon_arcade' => {
      label: 'Neon arcade',
      description: 'Morado neon, cyan electrico y azul brillante inspirado en estetica gamer retro.',
      preview: {
        background: 'radial-gradient(circle at 22% 20%, rgba(95, 247, 255, 0.30) 0%, rgba(95, 247, 255, 0) 36%), radial-gradient(circle at 84% 12%, rgba(200, 91, 255, 0.36) 0%, rgba(200, 91, 255, 0) 34%), linear-gradient(135deg, #090d31 0%, #26125a 52%, #451a7a 100%)',
        ring: 'rgba(95, 247, 255, 0.35)',
        glow: 'rgba(200, 91, 255, 0.34)',
        text: '#ecfeff',
        badge_background: 'rgba(13, 18, 57, 0.58)',
        badge_text: '#9cfbff'
      },
      css: {
        'theme-shell-bg-start' => '#070a25',
        'theme-shell-bg-mid' => '#1a0d45',
        'theme-shell-bg-end' => '#32105f',
        'theme-shell-glow-1' => 'rgba(95, 247, 255, 0.26)',
        'theme-shell-glow-2' => 'rgba(200, 91, 255, 0.28)',
        'theme-selection-bg' => '#5ff7ff',
        'theme-selection-text' => '#120a2f',
        'theme-glass-bg' => 'rgba(10, 14, 45, 0.62)',
        'theme-glass-border' => 'rgba(95, 247, 255, 0.24)',
        'theme-card-border' => 'rgba(200, 91, 255, 0.26)',
        'theme-nav-active-bg' => 'rgba(200, 91, 255, 0.34)',
        'theme-nav-active-text' => '#f4e8ff',
        'theme-nav-hover-bg' => 'rgba(200, 91, 255, 0.28)',
        'theme-nav-hover-text' => '#f0ddff',
        'theme-nav-logo-start' => '#c85bff',
        'theme-nav-logo-end' => '#5ff7ff',
        'theme-nav-logo-shadow' => 'rgba(95, 247, 255, 0.34)',
        'theme-surface-hero-border' => 'rgba(95, 247, 255, 0.34)',
        'theme-surface-hero-from' => '#0e1037',
        'theme-surface-hero-via' => '#26145f',
        'theme-surface-hero-to' => '#3e1574',
        'theme-surface-hero-kicker-bg' => 'rgba(13, 18, 57, 0.58)',
        'theme-surface-hero-kicker-border' => 'rgba(95, 247, 255, 0.35)',
        'theme-surface-hero-kicker-text' => '#9cfbff',
        'theme-surface-hero-heading' => '#f4e8ff',
        'theme-surface-hero-body' => 'rgba(225, 247, 255, 0.9)',
        'theme-surface-hero-orb-primary' => 'rgba(95, 247, 255, 0.24)',
        'theme-surface-hero-orb-secondary' => 'rgba(200, 91, 255, 0.28)',
        'theme-surface-panel-border' => 'rgba(95, 247, 255, 0.28)',
        'theme-surface-panel-from' => '#0a0d33',
        'theme-surface-panel-via' => '#1b1452',
        'theme-surface-panel-to' => '#35126b',
        'theme-surface-panel-heading' => '#f6eeff',
        'theme-surface-panel-body' => 'rgba(223, 246, 255, 0.82)',
        'theme-surface-panel-icon' => '#7cf9ff',
        'theme-surface-summary-border' => 'rgba(200, 91, 255, 0.30)',
        'theme-surface-summary-from' => '#120f3f',
        'theme-surface-summary-via' => '#26125b',
        'theme-surface-summary-to' => '#391874',
        'theme-surface-summary-total' => '#7bf7ff',
        'theme-pay-button-from' => '#b645ff',
        'theme-pay-button-to' => '#30e9ff',
        'theme-pay-button-shadow' => 'rgba(163, 68, 255, 0.42)',
        'theme-pay-button-hover-from' => '#d360ff',
        'theme-pay-button-hover-to' => '#60f6ff',
        'theme-sky-50' => '#f2f5ff',
        'theme-sky-100' => '#e8ebff',
        'theme-sky-200' => '#d9ddff',
        'theme-sky-300' => '#b8c0ff',
        'theme-sky-500' => '#6f88ff',
        'theme-sky-600' => '#5a72f7',
        'theme-sky-700' => '#465ce0',
        'theme-sky-800' => '#3445b8',
        'theme-sky-900' => '#242f85',
        'theme-cyan-50' => '#effeff',
        'theme-cyan-100' => '#ddfdff',
        'theme-cyan-200' => '#bdf9ff',
        'theme-cyan-400' => '#5ff7ff',
        'theme-cyan-500' => '#30e9ff',
        'theme-cyan-600' => '#06cbe6',
        'theme-cyan-700' => '#00a8c7',
        'theme-input-border' => '#6defff',
        'theme-input-focus' => '#c85bff',
        'theme-input-shadow' => 'rgba(200, 91, 255, 0.28)',
        'theme-focus-ring' => 'rgba(95, 247, 255, 0.26)',
        'theme-accent-shadow' => 'rgba(200, 91, 255, 0.34)'
      }
    }
  }.freeze

  has_many :productos, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :categorias, dependent: :destroy
  has_many :profit_margin_presets, dependent: :destroy
  has_many :suppliers, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :purchase_invoices, class_name: 'PurchaseInvoice', foreign_key: :business_id, dependent: :destroy
  has_many :clientes, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :ventas, dependent: :destroy
  has_many :venta_payments, through: :ventas
  has_many :cash_shifts, dependent: :destroy
  has_many :cambio_efectivos, dependent: :destroy
  has_many :pack_unwraps, dependent: :destroy
  has_many :product_usages, dependent: :destroy
  has_many :expenses, dependent: :destroy
  has_many :expense_payments, through: :expenses
  has_many :debts, dependent: :destroy
  has_many :debt_payments, through: :debts
  has_one_attached :logo
  has_one_attached :banner

  validates :name, presence: true
  validates :theme_profile, presence: true, inclusion: { in: THEME_PROFILES.keys }
  validate :validate_logo_attachment
  validate :validate_banner_attachment

  before_validation :set_default_theme_profile
  after_create :seed_shared_accounts

  def self.theme_profile_config(profile = DEFAULT_THEME_PROFILE)
    THEME_PROFILES[profile.presence || DEFAULT_THEME_PROFILE] || THEME_PROFILES[DEFAULT_THEME_PROFILE]
  end

  def self.theme_profile_options
    THEME_PROFILES.map { |key, data| [data[:label], key] }
  end

  def self.theme_css_variables(profile = DEFAULT_THEME_PROFILE)
    theme_profile_config(profile).fetch(:css).map { |name, value| "--#{name}: #{value}" }.join('; ')
  end

  def current_open_cash_shift
    cash_shifts.where(status: 'open').order(opened_at: :desc).first
  end

  def self.theme_preview_style(profile = DEFAULT_THEME_PROFILE)
    preview = theme_profile_config(profile).fetch(:preview)
    [
      "background: #{preview.fetch(:background)}",
      "box-shadow: 0 18px 45px -24px #{preview.fetch(:glow)}",
      "border: 1px solid #{preview.fetch(:ring)}",
      "color: #{preview.fetch(:text)}"
    ].join('; ')
  end

  def self.theme_preview_badge_style(profile = DEFAULT_THEME_PROFILE)
    preview = theme_profile_config(profile).fetch(:preview)
    [
      "background: #{preview.fetch(:badge_background)}",
      "color: #{preview.fetch(:badge_text)}",
      "border: 1px solid #{preview.fetch(:ring)}"
    ].join('; ')
  end

  def theme_config
    self.class.theme_profile_config(theme_profile)
  end

  def theme_css_variables
    self.class.theme_css_variables(theme_profile)
  end

  def theme_label
    theme_config.fetch(:label)
  end

  def theme_description
    theme_config.fetch(:description)
  end

  def theme_preview_style
    self.class.theme_preview_style(theme_profile)
  end

  def theme_preview_badge_style
    self.class.theme_preview_badge_style(theme_profile)
  end

  private

  def validate_logo_attachment
    validate_image_attachment(:logo, max_size: 5.megabytes)
  end

  def validate_banner_attachment
    validate_image_attachment(:banner, max_size: 8.megabytes)
  end

  def validate_image_attachment(attachment_name, max_size:)
    attachment = public_send(attachment_name)
    return unless attachment.attached?

    unless attachment.blob.content_type.in?(%w[image/png image/jpeg image/jpg image/webp image/svg+xml image/gif])
      errors.add(attachment_name, 'debe ser una imagen valida (PNG, JPG, WEBP, SVG o GIF).')
    end

    return unless attachment.blob.byte_size > max_size

    errors.add(attachment_name, "debe pesar menos de #{max_size / 1.megabyte}MB.")
  end

  private

  def set_default_theme_profile
    self.theme_profile = DEFAULT_THEME_PROFILE if theme_profile.blank?
  end

  def seed_shared_accounts
    master_business = Business.order(:created_at).first

    if master_business.blank? || master_business.id == id
      Account.ensure_special_accounts!(self)
      Account.ensure_cash_accounts!(self)
      return
    end

    Account.seed_from_master!(master_business, self)
    Account.ensure_cash_accounts!(self)
  end
end
