require 'test_helper'
require 'securerandom'

class ServiceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'invalid when caution and restricted flags are both enabled' do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    service = business.services.new(
      description: 'Servicio sensible',
      pricing_mode: 'to_agree',
      available: true,
      caution_service: true,
      restricted_service: true
    )

    assert_not service.valid?
    assert_includes service.errors[:restricted_service], 'no puede combinarse con servicio con precaucion'
    assert_includes service.errors[:caution_service], 'no puede combinarse con servicio restringido'
  end

  test 'show permission obeys availability and restricted status for non admins' do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")
    staff_user = User.new(admin: false)
    admin_user = User.new(admin: true)

    service = business.services.create!(
      description: 'Servicio publico',
      pricing_mode: 'to_agree',
      available: true,
      restricted_service: false,
      caution_service: false
    )

    assert service.show_allowed_for?(staff_user)

    service.update!(available: false)
    assert_not service.show_allowed_for?(staff_user)
    assert service.show_allowed_for?(admin_user)

    service.update!(available: true, restricted_service: true)
    assert_not service.show_allowed_for?(staff_user)
    assert service.show_allowed_for?(admin_user)
  end

  test 'auto cost stock discount requires cost flag and at least one expense structure' do
    business = Business.create!(name: "Business #{SecureRandom.hex(3)}")

    without_cost = business.services.new(
      description: 'Servicio auto sin gastos',
      pricing_mode: 'to_agree',
      available: true,
      cost: false,
      auto_cost_stock_discount: true
    )

    assert_not without_cost.valid?
    assert_includes without_cost.errors[:auto_cost_stock_discount], 'requiere activar la opcion "Conlleva gastos"'

    without_structures = business.services.new(
      description: 'Servicio auto sin estructura',
      pricing_mode: 'to_agree',
      available: true,
      cost: true,
      auto_cost_stock_discount: true
    )

    assert_not without_structures.valid?
    assert_includes without_structures.errors[:auto_cost_stock_discount],
                    'requiere al menos una estructura de gastos activa'

    valid_service = business.services.new(
      description: 'Servicio auto valido',
      pricing_mode: 'to_agree',
      available: true,
      cost: true,
      auto_cost_stock_discount: true
    )
    valid_service.service_expense_structures.build(description: 'Base')

    assert valid_service.valid?
  end
end
