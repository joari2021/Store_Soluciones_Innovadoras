require "test_helper"
require "securerandom"

class ServicesControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ["users"]
  fixtures :users

  setup do
    @admin = users(:jorge)
    @staff = users(:maria)

    @business = Business.create!(name: "Negocio Servicios #{SecureRandom.hex(3)}")
    @other_business = Business.create!(name: "Negocio Alterno #{SecureRandom.hex(3)}")

    @service = create_service_for(@business, description: "Servicio propio")
    @other_service = create_service_for(@other_business, description: "Servicio ajeno")

    login_and_select_business!(@admin, password: "215150603", business: @business)
  end

  test "index shows only services from current business" do
    get services_path

    assert_response :success
    assert_includes response.body, @service.description
    refute_includes response.body, @other_service.description
  end

  test "show returns not found for service from another business" do
    get service_path(@other_service)

    assert_response :not_found
  end

  test "index hides restricted services for non admin users" do
    restricted_service = create_service_for(
      @business,
      description: "Servicio solo admin",
      restricted_service: true,
    )
    visible_service = create_service_for(@business, description: "Servicio visible")

    login_and_select_business!(@staff, password: "testme", business: @business)

    get services_path

    assert_response :success
    assert_includes response.body, visible_service.description
    refute_includes response.body, restricted_service.description
  end

  test "index shows restricted services for admins" do
    restricted_service = create_service_for(
      @business,
      description: "Servicio restringido admin",
      restricted_service: true,
    )

    get services_path

    assert_response :success
    assert_includes response.body, restricted_service.description
  end

  test "show blocks unavailable service for non admin users" do
    unavailable_service = create_service_for(
      @business,
      description: "Servicio no disponible",
      available: false,
    )

    login_and_select_business!(@staff, password: "testme", business: @business)

    get service_path(unavailable_service)

    assert_response :forbidden
    assert_includes response.body, "no esta disponible"
  end

  test "show blocks restricted service for non admin users" do
    restricted_service = create_service_for(
      @business,
      description: "Servicio reservado admin",
      restricted_service: true,
    )

    login_and_select_business!(@staff, password: "testme", business: @business)

    get service_path(restricted_service)

    assert_response :forbidden
    assert_includes response.body, "solo puede verlo el administrador"
  end

  test "create assigns service to current business" do
    assert_difference("Service.count", 1) do
      post services_path, params: {
                            service: {
                              description: "Servicio nuevo",
                              pricing_mode: "to_agree",
                              available: "1",
                              business_id: @other_business.id,
                            },
                          }
    end

    assert_redirected_to services_path
    assert_equal @business.id, Service.order(:id).last.business_id
  end

  test "pending_costs lists sold services in table format" do
    sold_service = create_service_for(@business, description: "Servicio vendido tabla")
    create_paid_sale_with_service_item!(service: sold_service, unit_price_usd: 15, quantity: 1)

    get pending_costs_services_path

    assert_response :success
    assert_includes response.body, "Servicios vendidos y estado de costos"
    assert_includes response.body, sold_service.description
    assert_includes response.body, "Sin costo"
  end

  test "pending_costs shows detail action for sold service rows with associated debt" do
    structured_service = create_service_for(
      @business,
      description: "Servicio con deuda visible",
      cost: true,
    )
    structured_service.service_expense_structures.create!(description: "Estructura costo")
    structured_service.update!(auto_cost_stock_discount: true)

    sale = create_paid_sale_with_service_item!(service: structured_service, unit_price_usd: 20, quantity: 1)
    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_id" => structured_service.id,
            "service_name" => structured_service.description,
            "quantity" => 1,
            "unit_cost_usd" => 10,
            "total_cost_usd" => 10,
            "paid_cost_usd" => 2,
            "pending_cost_usd" => 8,
            "detail_lines" => [
              {
                "line_id" => "line-summary",
                "classification" => "variable_expense",
                "classification_label" => "Gasto variable",
                "source_name" => "Proveedor resumen",
                "amount_usd" => 10.0,
                "paid_usd" => 2.0,
                "pending_usd" => 8.0,
                "status" => "partial",
              },
            ],
          },
        ],
      }.to_json,
    )

    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-summary",
                                                    "structure_description" => "Estructura resumen",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Proveedor resumen",
                                                    "amount_usd" => 10.0,
                                                    "paid_usd" => 2.0,
                                                    "pending_usd" => 8.0,
                                                    "status" => "partial",
                                                    "source_updatable" => false,
                                                  },
                                                ])
    debt.update!(service: structured_service, venta: sale)

    get pending_costs_services_path

    assert_response :success
    assert_select "table"
    assert_select "a[href='#{pending_cost_detail_services_path(debt_id: debt.id)}']", text: /Ver detalle/
  end

  test "pending_costs filters sold services by manager assigned in cost structures" do
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)
    manager = Manager.create!(name: "Gestor filtro tabla")

    service_with_manager = create_service_for(
      @business,
      description: "Servicio con gestor asociado",
      cost: true,
    )
    service_without_manager = create_service_for(@business, description: "Servicio sin gestor")

    structure = service_with_manager.service_expense_structures.create!(
      description: "Estructura gestor",
      active_for_sales: true,
    )
    structure.service_manager_expenses.create!(
      manager: manager,
      currency_reference: "Dolar BCV",
      amount_reference: 1,
    )

    create_paid_sale_with_service_item!(service: service_with_manager, unit_price_usd: 18, quantity: 1)
    create_paid_sale_with_service_item!(service: service_without_manager, unit_price_usd: 12, quantity: 1)

    get pending_costs_services_path, params: { manager_id: manager.id }

    assert_response :success
    assert_includes response.body, service_with_manager.description
    refute_includes response.body, service_without_manager.description
  end

  test "pending_costs keeps historical sales as no cost when structure is activated later" do
    service = create_service_for(
      @business,
      description: "Servicio sin estructura activa historico",
      cost: true,
      auto_cost_stock_discount: true,
    )
    structure = service.service_expense_structures.create!(
      description: "Estructura desactivada",
      active_for_sales: false,
    )

    create_paid_sale_with_service_item!(service: service, unit_price_usd: 20, quantity: 1)
    structure.update!(active_for_sales: true)

    get pending_costs_services_path

    assert_response :success
    assert_includes response.body, service.description
    assert_includes response.body, "Sin costo"
  end

  test "pending_costs includes nested sold services with nested label" do
    parent_service = create_service_for(
      @business,
      description: "Servicio padre anidado",
      cost: true,
    )
    parent_structure = parent_service.service_expense_structures.create!(description: "Estructura padre")
    parent_service.update!(auto_cost_stock_discount: true)

    nested_service = create_service_for(
      @business,
      description: "Servicio hijo anidado",
      nested_available: true,
      cost: true,
    )
    nested_service.service_expense_structures.create!(description: "Estructura nested")
    nested_service.update!(auto_cost_stock_discount: true)
    nested_expense = parent_structure.service_nested_expenses.create!(
      nested_service: nested_service,
      quantity: 1,
      currency_reference: "Bs",
      amount_reference: 100,
    )

    sale = create_paid_sale_with_service_item!(service: parent_service, unit_price_usd: 25, quantity: 1)
    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_id" => parent_service.id,
            "service_name" => parent_service.description,
            "quantity" => 1,
            "unit_cost_usd" => 5,
            "total_cost_usd" => 5,
            "paid_cost_usd" => 0,
            "pending_cost_usd" => 5,
            "detail_lines" => [
              {
                "line_id" => "nested-line-1",
                "classification" => "nested_expense",
                "source_type" => "ServiceNestedExpense",
                "source_id" => nested_expense.id,
                "source_name" => nested_service.description,
                "quantity" => 1,
                "amount_usd" => 5,
              },
            ],
          },
        ],
      }.to_json,
    )

    get pending_costs_services_path

    assert_response :success
    assert_includes response.body, nested_service.description
    assert_includes response.body, "Anidado"
    assert_includes response.body, "Desde:"
  end

  test "pending_cost_detail renders base amount section when line has reference currency" do
    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-bs",
                                                    "structure_description" => "Estructura Bs",
                                                    "classification" => "manager_expense",
                                                    "classification_label" => "Gestor",
                                                    "source_name" => "Gestor Bs",
                                                    "amount_usd" => 10.0,
                                                    "paid_usd" => 2.0,
                                                    "pending_usd" => 8.0,
                                                    "status" => "partial",
                                                    "source_updatable" => true,
                                                    "source_currency_reference" => "Bs",
                                                    "source_amount_reference_unit" => 400.0,
                                                    "source_amount_reference_total" => 400.0,
                                                  },
                                                ])

    get pending_cost_detail_services_path(debt_id: debt.id)

    assert_response :success
    assert_includes response.body, "Total base (Bs)"
    assert_includes response.body, "Pendiente base (Bs)"
    assert_includes response.body, "Registrar pago parcial"
    assert_includes response.body, "Registrar pago total"
  end

  test "pending_cost_detail hides source update checkbox for non updatable lines" do
    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-no-sync",
                                                    "structure_description" => "Estructura fija",
                                                    "classification" => "product_expense",
                                                    "classification_label" => "Consumible",
                                                    "source_name" => "Consumible fijo",
                                                    "amount_usd" => 10.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 10.0,
                                                    "status" => "pending",
                                                    "source_updatable" => false,
                                                  },
                                                ])

    get pending_cost_detail_services_path(debt_id: debt.id)

    assert_response :success
    refute_includes response.body, "Actualizar costo fuente de esta clasificacion"
    assert_includes response.body, "Esta clasificacion no sincroniza costo fuente."
  end

  test "pending_costs blocks non admin users" do
    login_and_select_business!(@staff, password: "testme", business: @business)

    get pending_costs_services_path

    assert_redirected_to root_path
  end

  test "pending_cost_rates returns currency rates for selected date" do
    date = Date.current
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: date)

    get pending_cost_rates_services_path, params: { fecha: date.strftime("%d-%m-%Y") }, as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal date.iso8601, payload.fetch("fecha_referencia")
    assert payload.fetch("rates").is_a?(Hash)
    assert payload.fetch("rates").key?("VES")
    assert_equal 1.0, payload.fetch("rates").fetch("VES")
  end

  test "pending_cost_rates rejects invalid date" do
    get pending_cost_rates_services_path, params: { fecha: "abc" }, as: :json

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_match(/Fecha invalida/i, payload.fetch("error"))
  end

  test "pay_pending_cost_line registers payment and updates selected line" do
    account = create_account_for(@business, name: "Caja USD", account_type: "cash_box", currency: "USD")
    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-a",
                                                    "structure_description" => "Estructura A",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Proveedor A",
                                                    "amount_usd" => 8.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 8.0,
                                                    "status" => "pending",
                                                    "source_updatable" => false,
                                                  },
                                                  {
                                                    "line_id" => "line-b",
                                                    "structure_description" => "Estructura B",
                                                    "classification" => "manager_expense",
                                                    "classification_label" => "Gestor",
                                                    "source_name" => "Gestor B",
                                                    "amount_usd" => 2.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 2.0,
                                                    "status" => "pending",
                                                    "source_updatable" => false,
                                                  },
                                                ])

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt.id,
                                                  line_id: "line-a",
                                                  account_id: account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "3.00",
                                                }
    end

    assert_redirected_to pending_costs_services_path

    debt.reload
    line_a = debt.service_cost_lines.find { |line| line["line_id"] == "line-a" }
    line_b = debt.service_cost_lines.find { |line| line["line_id"] == "line-b" }

    assert_equal BigDecimal("3.0"), line_a["paid_usd"].to_d
    assert_equal BigDecimal("5.0"), line_a["pending_usd"].to_d
    assert_equal "partial", line_a["status"]

    assert_equal BigDecimal("0.0"), line_b["paid_usd"].to_d
    assert_equal BigDecimal("2.0"), line_b["pending_usd"].to_d
    assert_equal "pending", line_b["status"]

    assert debt.service_cost_pending?
    payment = debt.debt_payments.order(:id).last
    assert_equal account.id, payment.account_id
    assert_includes payment.notes.to_s, "[LINE:line-a]"
  end

  test "pay_pending_cost_line updates source cost when requested for updatable line" do
    account = create_account_for(@business, name: "Caja Bs", account_type: "cash_box", currency: "VES")
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)
    structure = @service.service_expense_structures.create!(description: "Estructura editable")
    variable_expense = structure.service_variable_expenses.create!(
      description: "Variable editable",
      currency_reference: "Dolar BCV",
      amount_reference: 1,
    )

    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-updatable",
                                                    "structure_description" => "Estructura editable",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Variable editable",
                                                    "quantity" => 2.0,
                                                    "amount_usd" => 4.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 4.0,
                                                    "status" => "pending",
                                                    "source_updatable" => true,
                                                    "source_type" => "ServiceVariableExpense",
                                                    "source_id" => variable_expense.id,
                                                    "source_currency_reference" => "Dolar BCV",
                                                    "source_amount_reference_unit" => 1.0,
                                                    "source_amount_reference_total" => 2.0,
                                                  },
                                                ])

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt.id,
                                                  line_id: "line-updatable",
                                                  account_id: account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "160.00",
                                                  update_source_cost: "1",
                                                }
    end

    assert_redirected_to pending_costs_services_path

    debt.reload
    line = debt.service_cost_lines.find { |row| row["line_id"] == "line-updatable" }

    assert_equal BigDecimal("4.0"), line["paid_usd"].to_d
    assert_equal BigDecimal("0.0"), line["pending_usd"].to_d
    assert_equal "paid", line["status"]
    refute debt.service_cost_pending?

    variable_expense.reload
    assert_equal BigDecimal("4.0"), variable_expense.amount_reference.to_d
    assert_equal BigDecimal("4.0"), line["source_amount_reference_unit"].to_d
    assert_equal BigDecimal("4.0"), line["source_amount_reference_total"].to_d
  end

  test "pay_pending_cost_line enforces account currency based on source reference" do
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)
    TasaCambio.create!(description: "USDT", valor: 40, fecha_referencia: Date.current)

    usd_account = create_account_for(@business, name: "Caja USD", account_type: "cash_box", currency: "USD")
    ves_account = create_account_for(@business, name: "Caja Bs", account_type: "cash_box", currency: "VES")
    usdt_account = create_account_for(@business, name: "Wallet USDT", account_type: "crypto_wallet", currency: "USDT")

    debt_dolar = create_pending_cost_debt_with_lines!([
                                                        {
                                                          "line_id" => "line-dolar",
                                                          "structure_description" => "Estructura dolar",
                                                          "classification" => "variable_expense",
                                                          "classification_label" => "Gasto variable",
                                                          "source_name" => "Costo dolar",
                                                          "amount_usd" => 5.0,
                                                          "paid_usd" => 0.0,
                                                          "pending_usd" => 5.0,
                                                          "status" => "pending",
                                                          "source_updatable" => false,
                                                          "source_currency_reference" => "Dolar BCV",
                                                          "source_amount_reference_unit" => 5.0,
                                                          "source_amount_reference_total" => 5.0,
                                                        },
                                                      ])

    assert_no_difference("DebtPayment.count") do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt_dolar.id,
                                                  line_id: "line-dolar",
                                                  account_id: usd_account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "5.00",
                                                }
    end

    assert_redirected_to pending_costs_services_path

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt_dolar.id,
                                                  line_id: "line-dolar",
                                                  account_id: ves_account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "200.00",
                                                }
    end

    debt_usdt = create_pending_cost_debt_with_lines!([
                                                       {
                                                         "line_id" => "line-usdt",
                                                         "structure_description" => "Estructura usdt",
                                                         "classification" => "variable_expense",
                                                         "classification_label" => "Gasto variable",
                                                         "source_name" => "Costo usdt",
                                                         "amount_usd" => 5.0,
                                                         "paid_usd" => 0.0,
                                                         "pending_usd" => 5.0,
                                                         "status" => "pending",
                                                         "source_updatable" => false,
                                                         "source_currency_reference" => "USDT",
                                                         "source_amount_reference_unit" => 5.0,
                                                         "source_amount_reference_total" => 5.0,
                                                       },
                                                     ])

    assert_no_difference("DebtPayment.count") do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt_usdt.id,
                                                  line_id: "line-usdt",
                                                  account_id: ves_account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "200.00",
                                                }
    end

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt_usdt.id,
                                                  line_id: "line-usdt",
                                                  account_id: usdt_account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "5.00",
                                                }
    end
  end

  test "pay_pending_cost_line total payment closes line and can update source with entered amount" do
    account = create_account_for(@business, name: "Caja Bs", account_type: "cash_box", currency: "VES")
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)
    structure = @service.service_expense_structures.create!(description: "Estructura total")
    variable_expense = structure.service_variable_expenses.create!(
      description: "Variable total",
      currency_reference: "Dolar BCV",
      amount_reference: 1,
    )

    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-total",
                                                    "structure_description" => "Estructura total",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Variable total",
                                                    "quantity" => 1.0,
                                                    "amount_usd" => 4.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 4.0,
                                                    "status" => "pending",
                                                    "source_updatable" => true,
                                                    "source_type" => "ServiceVariableExpense",
                                                    "source_id" => variable_expense.id,
                                                    "source_currency_reference" => "Dolar BCV",
                                                    "source_amount_reference_unit" => 1.0,
                                                    "source_amount_reference_total" => 1.0,
                                                  },
                                                ])

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt.id,
                                                  line_id: "line-total",
                                                  account_id: account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "150.00",
                                                  payment_scope: "total",
                                                  force_total_settlement: "1",
                                                  update_source_cost_override: "1",
                                                }
    end

    debt.reload
    line = debt.service_cost_lines.find { |row| row["line_id"] == "line-total" }

    assert_equal BigDecimal("4.0"), line["paid_usd"].to_d
    assert_equal BigDecimal("0.0"), line["pending_usd"].to_d
    assert_equal "paid", line["status"]
    refute debt.service_cost_pending?

    payment = debt.debt_payments.order(:id).last
    assert_equal BigDecimal("4.0"), payment.amount_in_debt_currency.to_d

    variable_expense.reload
    assert_equal BigDecimal("3.75"), variable_expense.amount_reference.to_d
    assert_equal BigDecimal("3.75"), line["source_amount_reference_unit"].to_d
    assert_equal BigDecimal("3.75"), line["source_amount_reference_total"].to_d
  end

  test "paid sold service keeps historical structure snapshot after source deletion" do
    account = create_account_for(@business, name: "Caja Bs", account_type: "cash_box", currency: "VES")
    TasaCambio.create!(description: "Dolar BCV", valor: 40, fecha_referencia: Date.current)

    structure = @service.service_expense_structures.create!(description: "Estructura historica")
    variable_expense = structure.service_variable_expenses.create!(
      description: "Variable historica",
      currency_reference: "Dolar BCV",
      amount_reference: 4,
    )

    sale = create_paid_sale_with_service_item!(service: @service, unit_price_usd: 20, quantity: 1)
    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_id" => @service.id,
            "service_name" => @service.description,
            "quantity" => 1,
            "unit_cost_usd" => 4,
            "total_cost_usd" => 4,
            "paid_cost_usd" => 0,
            "pending_cost_usd" => 4,
            "detail_lines" => [
              {
                "line_id" => "line-historica",
                "structure_description" => "Estructura historica",
                "classification" => "variable_expense",
                "classification_label" => "Gasto variable",
                "source_name" => "Variable historica",
                "amount_usd" => 4,
                "paid_usd" => 0,
                "pending_usd" => 4,
                "status" => "pending",
              },
            ],
          },
        ],
      }.to_json,
    )

    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-historica",
                                                    "structure_description" => "Estructura historica",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Variable historica",
                                                    "quantity" => 1.0,
                                                    "amount_usd" => 4.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 4.0,
                                                    "status" => "pending",
                                                    "source_updatable" => true,
                                                    "source_type" => "ServiceVariableExpense",
                                                    "source_id" => variable_expense.id,
                                                    "source_currency_reference" => "Dolar BCV",
                                                    "source_amount_reference_unit" => 4.0,
                                                    "source_amount_reference_total" => 4.0,
                                                  },
                                                ])
    debt.update!(service: @service, venta: sale)

    assert_difference("DebtPayment.count", 1) do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt.id,
                                                  line_id: "line-historica",
                                                  account_id: account.id,
                                                  payment_date: Date.current.strftime("%d-%m-%Y"),
                                                  amount: "160.00",
                                                  payment_scope: "total",
                                                  force_total_settlement: "1",
                                                }
    end

    debt.reload
    refute debt.service_cost_pending?

    structure.destroy!

    get pending_cost_detail_services_path(debt_id: debt.id)
    assert_response :success
    assert_includes response.body, "Estructura historica"
    assert_includes response.body, "Variable historica"
    assert_includes response.body, "Linea saldada"

    notes_payload = JSON.parse(sale.reload.notes)
    settlement = Array(notes_payload["service_cost_settlements"]).find do |row|
      row.is_a?(Hash) && row["service_id"].to_i == @service.id
    end

    assert settlement.present?
    assert_equal BigDecimal("4.0"), settlement["paid_cost_usd"].to_d
    assert_equal BigDecimal("0.0"), settlement["pending_cost_usd"].to_d

    line = Array(settlement["detail_lines"]).find { |row| row["line_id"] == "line-historica" }
    assert line.present?
    assert_equal "Estructura historica", line["structure_description"]
    assert_equal "paid", line["status"]
  end

  test "pay_pending_cost_line requires bank metadata for bank account payments" do
    bank_account = create_account_for(@business, name: "Banco USD", account_type: "bank_account", currency: "USD")
    debt = create_pending_cost_debt_with_lines!([
                                                  {
                                                    "line_id" => "line-bank",
                                                    "structure_description" => "Estructura banco",
                                                    "classification" => "variable_expense",
                                                    "classification_label" => "Gasto variable",
                                                    "source_name" => "Banco",
                                                    "amount_usd" => 5.0,
                                                    "paid_usd" => 0.0,
                                                    "pending_usd" => 5.0,
                                                    "status" => "pending",
                                                    "source_updatable" => false,
                                                  },
                                                ])

    assert_no_difference("DebtPayment.count") do
      post pay_pending_cost_line_services_path, params: {
                                                  debt_id: debt.id,
                                                  line_id: "line-bank",
                                                  account_id: bank_account.id,
                                                  amount: "1.00",
                                                }
    end

    assert_redirected_to pending_costs_services_path

    debt.reload
    line = debt.service_cost_lines.find { |row| row["line_id"] == "line-bank" }
    assert_equal BigDecimal("0.0"), line["paid_usd"].to_d
    assert_equal BigDecimal("5.0"), line["pending_usd"].to_d
    assert debt.service_cost_pending?
  end

  private

  def create_pending_cost_debt_with_lines!(lines)
    total_usd = lines.sum { |line| line["amount_usd"].to_d }.round(2)
    paid_usd = lines.sum { |line| line["paid_usd"].to_d }.round(2)
    pending_usd = lines.sum { |line| line["pending_usd"].to_d }.round(2)

    @business.debts.create!(
      name: "Costo servicio pendiente",
      debt_kind: "payable",
      amount: total_usd,
      currency: "USD",
      issued_on: Date.current,
      service_cost_pending: pending_usd.positive?,
      service: @service,
      service_cost_details: {
        "version" => 1,
        "service_id" => @service.id,
        "service_name" => @service.description,
        "total_usd" => total_usd.to_f,
        "paid_usd" => paid_usd.to_f,
        "pending_usd" => pending_usd.to_f,
        "status" => if pending_usd.positive?
          paid_usd.positive? ? "partial" : "pending"
        else
          "paid"
        end,
        "lines" => lines,
      },
    )
  end

  def create_paid_sale_with_service_item!(service:, unit_price_usd:, quantity:, sold_at: Time.current)
    sale = @business.ventas.create!(
      status: "paid",
      vat_mode: "none",
      vat_rate: 0.16,
      base_currency: "USD",
      tasa_dolar: 40,
      user: @admin,
      notes: {}.to_json,
    )

    subtotal_usd = (unit_price_usd.to_d * quantity.to_d).round(2)
    sale.venta_items.create!(
      product_name: service.description,
      variation_name: service.system_service&.name.presence || "Servicio",
      quantity: quantity,
      unit_price_usd: unit_price_usd,
      subtotal_usd: subtotal_usd,
    )

    sale.update_columns(
      subtotal_usd: subtotal_usd,
      vat_usd: 0,
      total_usd: subtotal_usd,
      total_bs: (subtotal_usd * 40.to_d).round(2),
      created_at: sold_at,
      updated_at: sold_at,
    )

    sale
  end

  def create_account_for(business, name:, account_type:, currency:)
    business.accounts.create!(
      name: name,
      account_type: account_type,
      currency: currency,
      balance: 1_000,
      active: true,
      theme_color: "sky",
    )
  end

  def create_service_for(business, description:, **attrs)
    base_attrs = {
      description: description,
      pricing_mode: "to_agree",
      available: true,
      restricted_service: false,
      caution_service: false,
    }

    business.services.create!(base_attrs.merge(attrs))
  end

  def login_and_select_business!(user, password:, business:)
    post sessions_path, params: { login: user.email, password: password }
    post select_business_path(business)
  end
end
