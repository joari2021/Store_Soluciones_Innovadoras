class User < ApplicationRecord
  has_secure_password
  SEX_OPTIONS = {
    'male' => 'Masculino',
    'female' => 'Femenino'
  }.freeze

  belongs_to :business, optional: true
  has_many :business_user_assignments, dependent: :destroy
  has_many :assigned_businesses, through: :business_user_assignments, source: :business
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
  validates :sex, inclusion: { in: SEX_OPTIONS.keys }, if: :supports_sex?

  # añadir cuando se añada la funcion de que varios otros usuarios puedan crear peliculas para asi monitorear luego
  # has_many :products, dependent: :destroy

  before_validation :normalize_role_flags
  before_validation :normalize_sex_value, if: :supports_sex?
  before_save :downcase_attributes

  def standard_staff?(business = Current.business)
    role_key(business) == 'standard_staff'
  end

  def manager?(business = Current.business)
    role_key(business) == 'manager'
  end

  def role_key(business = Current.business)
    return 'administrator' if admin?

    assignment = assignment_for_business(business)
    assignment_customer_level = assignment&.customer_access_level.to_s
    return 'catalog_viewer' if assignment_customer_level == 'catalog_viewer'
    return 'customer' if %w[customer customer_vip].include?(assignment_customer_level)

    assignment_level = assignment&.authorization_level.to_s
    return 'manager' if assignment_level == 'administrator'
    return assignment_level if %w[none manager standard_staff].include?(assignment_level)

    'none'
  end

  def customer_access_level(business = Current.business)
    assignment = assignment_for_business(business)
    return 'none' if assignment.blank?

    level = assignment.customer_access_level.to_s
    return level if BusinessUserAssignment::CUSTOMER_ACCESS_LEVELS.include?(level)

    'none'
  end

  def catalog_viewer_mode?(business = Current.business)
    assignment = assignment_for_business(business)
    assignment&.customer_access_level.to_s == 'catalog_viewer'
  end

  def customer_mode?(business = Current.business)
    return false if admin?
    %w[customer customer_vip].include?(customer_access_level(business))
  end

  def customer_vip_mode?(business = Current.business)
    customer_mode?(business) && customer_access_level(business) == 'customer_vip'
  end

  def role_label(business = Current.business)
    return female? ? 'Administradora' : 'Administrador' if admin?
    return 'Catalogo' if catalog_viewer_mode?(business)
    return 'Cliente' if customer_mode?(business)
    return female? ? 'Encargada' : 'Encargado' if manager?(business)
    return 'Sin cargo' if role_key(business) == 'none'

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
    effective_business = Current.business
    if effective_business.blank? && !admin?
      effective_business = business_user_assignments.active.order(:business_id).limit(1).pick(:business_id) || business_id
    end

    return false unless active_for_business?(effective_business)
    return true if admin?

    # Bypass temporal para diagnostico: no restringir vistas por modulo a usuarios de catalogo.
    return true if catalog_viewer_mode?(effective_business)

    if customer_mode?(effective_business)
      return %i[ventas historial_ventas deudas].include?(module_key.to_sym)
    end

    case module_key.to_sym
    when :ventas, :historial_ventas, :productos, :deudas, :services, :rates, :clientes, :cash_shifts
      true
    when :accounts
      manager?(effective_business)
    else
      false
    end
  end

  def can_manage_action?(action_key)
    return false unless active_for_business?(Current.business)
    return true if admin?

    return false if customer_mode?(Current.business) || catalog_viewer_mode?(Current.business)

    allowed_actions = %i[manage_clients create_debt register_debt_payment update_rates]
    allowed_actions << :manage_cash_shifts if manager?(Current.business)

    allowed_actions.include?(action_key.to_sym)
  end

  def assignment_for_business(business)
    business_id = business.is_a?(Business) ? business.id : business
    return nil if business_id.blank?

    if business_user_assignments.loaded?
      business_user_assignments.find { |assignment| assignment.business_id == business_id.to_i }
    else
      business_user_assignments.find_by(business_id: business_id)
    end
  end

  def assigned_to_business?(business)
    return true if admin?

    assignment = assignment_for_business(business)
    assignment.present? && assignment.active?
  end

  def active_for_business?(business)
    return false unless active?
    return true if admin?

    assignment = assignment_for_business(business)
    assignment.present? && assignment.active?
  end

  private

  def normalize_role_flags
    if admin?
      self.personal = false
      self.personal_saime = true if has_attribute?(:personal_saime) && personal_saime.nil?
      return
    end

    self.admin = false
    self.personal = true if has_attribute?(:personal) && personal.nil?
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
