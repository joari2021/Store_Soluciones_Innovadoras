require "test_helper"
require "securerandom"

class ServiceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "invalid when caution and restricted flags are both enabled" do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    service = business.services.new(
      description: "Servicio sensible",
      pricing_mode: "to_agree",
      available: true,
      caution_service: true,
      restricted_service: true,
    )

    assert_not service.valid?
    assert_includes service.errors[:restricted_service], "no puede combinarse con servicio con precaucion"
    assert_includes service.errors[:caution_service], "no puede combinarse con servicio restringido"
  end

  test "show permission obeys availability and restricted status for non admins" do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    staff_user = User.new(admin: false)
    admin_user = User.new(admin: true)

    service = business.services.create!(
      description: "Servicio publico",
      pricing_mode: "to_agree",
      available: true,
      restricted_service: false,
      caution_service: false,
    )

    assert service.show_allowed_for?(staff_user)

    service.update!(available: false)
    assert_not service.show_allowed_for?(staff_user)
    assert service.show_allowed_for?(admin_user)

    service.update!(available: true, restricted_service: true)
    assert_not service.show_allowed_for?(staff_user)
    assert service.show_allowed_for?(admin_user)
  end

  test "auto cost stock discount requires only cost flag" do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")

    without_cost = business.services.new(
      description: "Servicio auto sin gastos",
      pricing_mode: "to_agree",
      available: true,
      cost: false,
      auto_cost_stock_discount: true,
    )

    assert_not without_cost.valid?
    assert_includes without_cost.errors[:auto_cost_stock_discount], 'requiere activar la opcion "Conlleva gastos"'

    without_structures = business.services.new(
      description: "Servicio auto sin estructura",
      pricing_mode: "to_agree",
      available: true,
      cost: true,
      auto_cost_stock_discount: true,
    )

    assert without_structures.valid?

    valid_service = business.services.new(
      description: "Servicio auto valido",
      pricing_mode: "to_agree",
      available: true,
      cost: true,
      auto_cost_stock_discount: true,
    )
    valid_service.service_expense_structures.build(description: "Base")

    assert valid_service.valid?
  end

  test "total_expense_usd can sum only active structures" do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)

    service = business.services.create!(
      description: "Servicio costos activos",
      pricing_mode: "to_agree",
      available: true,
      cost: true,
    )

    active_structure = service.service_expense_structures.create!(
      description: "Estructura activa",
      active_for_sales: true,
    )
    inactive_structure = service.service_expense_structures.create!(
      description: "Estructura inactiva",
      active_for_sales: false,
    )

    active_structure.service_variable_expenses.create!(
      description: "Activo",
      currency_reference: "Dolar BCV",
      amount_reference: 2,
    )
    inactive_structure.service_variable_expenses.create!(
      description: "Inactivo",
      currency_reference: "Dolar BCV",
      amount_reference: 3,
    )

    assert_equal BigDecimal("5.0"), service.total_expense_usd(tasa_dolar: 40)
    assert_equal BigDecimal("2.0"), service.total_expense_usd(tasa_dolar: 40, active_only: true)
  end

  test "invalid when more than one expense structure is active for sales" do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    service = business.services.new(
      description: "Servicio estructuras exclusivas",
      pricing_mode: "to_agree",
      available: true,
      cost: true,
    )

    service.service_expense_structures.build(description: "Estructura A", active_for_sales: true)
    service.service_expense_structures.build(description: "Estructura B", active_for_sales: true)

    assert_not service.valid?
    assert_includes service.errors[:base], "Solo puedes marcar una estructura de gastos como activa en ventas."
  end
end
