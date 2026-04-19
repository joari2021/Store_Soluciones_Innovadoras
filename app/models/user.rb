class User < ApplicationRecord
  has_secure_password

  MIN_PASSWORD_LENGTH = 10
  PASSWORD_COMPLEXITY_REGEX = /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).+\z/.freeze
  AUTHORIZATION_LEVELS = %w[administrator manager standard_staff].freeze
  SEX_OPTIONS = {
    'male' => 'Masculino',
    'female' => 'Femenino'
  }.freeze

  belongs_to :business, optional: true
  has_many :ventas, dependent: :nullify
  has_many :opened_cash_shifts, class_name: 'CashShift', foreign_key: :opened_by_id, inverse_of: :opened_by,
                                dependent: :restrict_with_error
  has_many :closed_cash_shifts, class_name: 'CashShift', foreign_key: :closed_by_id, inverse_of: :closed_by,
                                dependent: :nullify
  has_many :product_usages, dependent: :restrict_with_error

  has_one_attached :avatar

  validates :email, presence: true, uniqueness: true,
                    format: {
                      with: /\A([\w+-].?)+@[a-z\d-]+(\.[a-z]+)*\.[a-z]+\z/i,
                      message: :invalid
                    }
  validates :username, presence: true, uniqueness: true,
                       length: { in: 3..15 },
                       format: {
                         with: /\A[a-z0-9A-Z]+\z/,
                         message: :invalid
                       }
  validates :full_name, length: { maximum: 80 }, allow_blank: true
  validates :password, length: { minimum: MIN_PASSWORD_LENGTH }, if: :password_required?
  validate :password_complexity, if: :password_required?
  validate :authorization_level_inclusion
  validates :sex, inclusion: { in: SEX_OPTIONS.keys }, if: :supports_sex?

  # añadir cuando se añada la funcion de que varios otros usuarios puedan crear peliculas para asi monitorear luego
  # has_many :products, dependent: :destroy

  before_validation :normalize_role_flags
  before_validation :normalize_sex_value, if: :supports_sex?
  before_save :downcase_attributes

  def standard_staff?
    role_key == 'standard_staff'
  end

  def manager?
    role_key == 'manager'
  end

  def role_key
    return 'administrator' if admin?

    if has_attribute?(:authorization_level)
      level = self[:authorization_level].to_s
      return 'manager' if level == 'manager'
    end

    'standard_staff'
  end

  def role_label
    return female? ? 'Administradora' : 'Administrador' if admin?
    return female? ? 'Encargada' : 'Encargado' if manager?

    'Personal estandar'
  end

  def sex_key
    return 'male' unless supports_sex?

    value = self[:sex].to_s
    return value if SEX_OPTIONS.key?(value)

    'male'
  end

  def female?
    sex_key == 'female'
  end

  def display_name
    full_name.to_s.strip.presence || username.to_s
  end

  def can_access_module?(module_key)
    return false unless active?
    return true if admin?

    case module_key.to_sym
    when :ventas, :historial_ventas, :productos, :deudas, :services, :rates, :clientes, :cash_shifts
      true
    when :accounts
      manager?
    else
      false
    end
  end

  def can_manage_action?(action_key)
    return false unless active?
    return true if admin?

    allowed_actions = %i[manage_clients create_debt register_debt_payment update_rates]
    allowed_actions << :manage_cash_shifts if manager?

    allowed_actions.include?(action_key.to_sym)
  end

  private

  def normalize_role_flags
    if admin?
      self.personal = false
      self.personal_saime = true if has_attribute?(:personal_saime) && personal_saime.nil?
      self[:authorization_level] = 'administrator' if has_attribute?(:authorization_level)
      return
    end

    self.admin = false
    self.personal = true if has_attribute?(:personal) && personal.nil?
    return unless has_attribute?(:authorization_level)

    current_level = self[:authorization_level].to_s
    self[:authorization_level] = 'standard_staff' if current_level.blank?
    return if %w[standard_staff manager].include?(self[:authorization_level])

    self[:authorization_level] = 'standard_staff'
  end

  def authorization_level_inclusion
    return unless has_attribute?(:authorization_level)

    level = self[:authorization_level].to_s
    return if AUTHORIZATION_LEVELS.include?(level)

    errors.add(:authorization_level, 'es invalido')
  end

  def password_required?
    password_digest_changed? || password.present?
  end

  def password_complexity
    return if password.blank?
    return if password.match?(PASSWORD_COMPLEXITY_REGEX)

    errors.add(:password, 'debe incluir mayusculas, minusculas, numeros y simbolos')
  end

  def downcase_attributes
    self.username = username.to_s.downcase
    self.email = email.to_s.downcase
    self.full_name = full_name.to_s.strip.presence
  end

  def supports_sex?
    has_attribute?(:sex)
  end

  def normalize_sex_value
    value = self[:sex].to_s
    self[:sex] = SEX_OPTIONS.key?(value) ? value : 'male'
  end
end
