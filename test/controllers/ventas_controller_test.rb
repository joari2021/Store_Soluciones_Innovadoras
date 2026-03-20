require "test_helper"
require "securerandom"

class VentasControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ["users"]
  fixtures :users

  setup do
    @user = users(:jorge)
    @business = Business.create!(name: "Negocio Ventas #{SecureRandom.hex(4)}")
    @categoria = @business.categorias.create!(nombre: "Categoria #{SecureRandom.hex(3)}")
    @supplier = @business.suppliers.create!(
      nombre: "Proveedor #{SecureRandom.hex(3)}",
      pricing_currency_priority: "usd",
    )
    @cash_account = @business.accounts.create!(
      name: "Caja Bs Ventas",
      account_type: "cash_box",
      currency: "VES",
      balance: 10_000,
      active: true,
      theme_color: "sky",
    )

    login_and_select_business!

    @open_cash_shift = @business.cash_shifts.create!(
      opened_by: @user,
      status: "open",
      opened_at: Time.current,
      opening_balance_ves: 0,
      opening_balance_usd: 0,
    )

    @product, @variation = create_product_with_stock!(
      available_units: 10,
      sale_price_usd: 10,
    )
  end

  test "save_draft reserves stock and returns draft payload" do
    assert_difference('Venta.where(status: "draft").count', 1) do
      post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json
    end

    assert_response :success

    payload = JSON.parse(response.body)
    draft_id = payload.dig("draft", "id")

    assert draft_id.present?
    assert_equal 8.to_d, stock_remaining_units
    assert_equal @business.id, Venta.find(draft_id).business_id
    assert_equal 1, payload.fetch("drafts").size
    assert payload["products"].is_a?(Array)
  end

  test "hidden draft reserves stock and is included in panel drafts list" do
    post "/ventas/save_draft",
         params: { venta: draft_payload(quantity: 2, draft_visibility: "hidden") },
         as: :json

    assert_response :success

    payload = JSON.parse(response.body)
    draft_id = payload.dig("draft", "id")

    assert draft_id.present?
    assert_equal "hidden", payload.dig("draft", "visibility")
    assert_equal 8.to_d, stock_remaining_units
    assert_equal 1, payload.fetch("drafts").size
    assert_equal "hidden", payload.fetch("drafts").first.fetch("visibility")
  end

  test "products_snapshot returns live products and all pending drafts" do
    post "/ventas/save_draft",
         params: { venta: draft_payload(quantity: 1, draft_visibility: "hidden") },
         as: :json
    post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json

    get "/ventas/products_snapshot", as: :json

    assert_response :success

    payload = JSON.parse(response.body)
    drafts = payload.fetch("drafts")
    visibilities = drafts.map { |draft| draft.fetch("visibility") }

    assert payload.fetch("products").is_a?(Array)
    assert_equal 2, drafts.size
    assert_includes visibilities, "hidden"
    assert_includes visibilities, "visible"
    assert_equal 7.to_d, stock_remaining_units
  end

  test "show_draft returns state used by load action" do
    post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json
    draft = Venta.where(status: "draft").order(:id).last

    get "/ventas/drafts/#{draft.id}", as: :json

    assert_response :success

    payload = JSON.parse(response.body)
    draft_json = payload.fetch("draft")
    state_items = draft_json.fetch("state").fetch("items")

    assert_equal draft.id, draft_json.fetch("id")
    assert_equal 1, state_items.size
    assert_equal @product.id, state_items.first.fetch("product_id")
    assert_equal @variation.id, state_items.first.fetch("variation_id")
    assert_equal 2.0, state_items.first.fetch("quantity").to_f
    assert payload["products"].is_a?(Array)
    assert payload["drafts"].is_a?(Array)
  end

  test "update_draft restores old reservation before applying new quantity" do
    post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json
    draft = Venta.where(status: "draft").order(:id).last

    patch "/ventas/drafts/#{draft.id}",
          params: { venta: draft_payload(quantity: 3, draft_id: draft.id) },
          as: :json

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal draft.id, payload.dig("draft", "id")
    assert_equal 7.to_d, stock_remaining_units
    assert_equal 3.to_d, draft.reload.venta_items.sum(&:quantity).to_d
  end

  test "destroy_draft restores stock and removes draft" do
    post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json
    draft = Venta.where(status: "draft").order(:id).last

    delete "/ventas/drafts/#{draft.id}", as: :json

    assert_response :success

    payload = JSON.parse(response.body)
    assert payload.fetch("success")
    assert_nil Venta.find_by(id: draft.id)
    assert_equal 10.to_d, stock_remaining_units
    assert payload["products"].is_a?(Array)
  end

  test "create from draft finalizes sale and consumes stock once" do
    post "/ventas/save_draft", params: { venta: draft_payload(quantity: 2) }, as: :json
    draft = Venta.where(status: "draft").order(:id).last

    assert_equal 8.to_d, stock_remaining_units

    assert_difference('Venta.where(status: "paid").count', 1) do
      post "/ventas",
           params: {
             venta: sale_payload(
               quantity: 2,
               draft_id: draft.id,
               paid_amount_ves: "800.00",
             ),
           },
           as: :json
    end

    assert_response :created

    payload = JSON.parse(response.body)
    paid_sale = Venta.where(status: "paid").order(:id).last

    assert_nil Venta.find_by(id: draft.id)
    assert_equal 8.to_d, stock_remaining_units
    assert_equal 1, paid_sale.venta_items.count
    assert_equal 1, paid_sale.venta_payments.count
    assert_equal 1, @cash_account.account_movements.where("description LIKE ?", "%[VENTA:#{paid_sale.id}]%").count
    assert payload["drafts"].is_a?(Array)
    assert payload["products"].is_a?(Array)
  end

  test "create preserves tasa_dolar provided at checkout as sale base rate" do
    TasaCambio.create!(description: "Dolar BCV", valor: 70, fecha_referencia: Date.current)

    assert_difference('Venta.where(status: "paid").count', 1) do
      post "/ventas", params: {
                        venta: {
                          vat_mode: "none",
                          vat_rate: "0.16",
                          tasa_dolar: "45.50",
                          base_currency: "USD",
                          items: [
                            {
                              item_type: "product",
                              product_id: @product.id,
                              variation_id: @variation.id,
                              quantity: "1",
                              unit_price_usd: @product.precio_venta_usd.to_s,
                            },
                          ],
                          payments: [
                            {
                              method: "cash",
                              amount: "455.00",
                              account_id: @cash_account.id,
                              currency: "VES",
                            },
                          ],
                        },
                      }, as: :json
    end

    assert_response :created

    sale = Venta.where(status: "paid").order(:id).last
    assert_equal BigDecimal("45.5"), sale.tasa_dolar.to_d
    assert_equal BigDecimal("455.0"), sale.total_bs.to_d
  end

  test "create requires selected client when remaining balance is marked as credit" do
    assert_no_difference("Debt.count") do
      post "/ventas", params: {
                        venta: {
                          vat_mode: "none",
                          vat_rate: "0.16",
                          tasa_dolar: "40",
                          base_currency: "USD",
                          items: [
                            {
                              item_type: "product",
                              product_id: @product.id,
                              variation_id: @variation.id,
                              quantity: "1",
                              unit_price_usd: @product.precio_venta_usd.to_s,
                            },
                          ],
                          payments: [
                            {
                              method: "cash",
                              amount: "200.00",
                              account_id: @cash_account.id,
                              currency: "VES",
                            },
                          ],
                          credit_sale: {
                            enabled: true,
                          },
                        },
                      }, as: :json
    end

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_match(/seleccionar un cliente/i, payload.fetch("error"))
  end

  test "create with partial credit creates receivable debt linked to sale and debt view link" do
    cliente = @business.clientes.create!(
      name: "Cliente Credito Parcial",
      document_type: "V",
      document_number: "#{SecureRandom.random_number(10 ** 8).to_s.rjust(8, "0")}",
    )
    due_on = Date.current + 5.days

    assert_difference("Debt.count", 1) do
      assert_difference('Venta.where(status: "paid").count', 1) do
        post "/ventas", params: {
                          venta: {
                            vat_mode: "none",
                            vat_rate: "0.16",
                            tasa_dolar: "40",
                            base_currency: "USD",
                            cliente_id: cliente.id,
                            items: [
                              {
                                item_type: "product",
                                product_id: @product.id,
                                variation_id: @variation.id,
                                quantity: "1",
                                unit_price_usd: @product.precio_venta_usd.to_s,
                              },
                            ],
                            payments: [
                              {
                                method: "cash",
                                amount: "200.00",
                                account_id: @cash_account.id,
                                currency: "VES",
                              },
                            ],
                            credit_sale: {
                              enabled: true,
                              due_on: due_on.iso8601,
                            },
                          },
                        }, as: :json
      end
    end

    assert_response :created

    sale = Venta.where(status: "paid").order(:id).last
    debt = Debt.order(:id).last

    assert_equal "receivable", debt.debt_kind
    assert_equal cliente.id, debt.cliente_id
    assert_equal "USD", debt.currency
    assert_equal BigDecimal("5.0"), debt.amount.to_d
    assert_equal due_on, debt.due_on
    assert_includes debt.description.to_s, "[VENTA:#{sale.id}]"

    get debt_path(debt)

    assert_response :success
    assert_includes response.body, venta_path(sale)
  end

  test "create full credit sale without payments creates receivable debt" do
    cliente = @business.clientes.create!(
      name: "Cliente Credito Total",
      document_type: "V",
      document_number: "#{SecureRandom.random_number(10 ** 8).to_s.rjust(8, "0")}",
    )

    assert_difference("Debt.count", 1) do
      assert_difference('Venta.where(status: "paid").count', 1) do
        post "/ventas", params: {
                          venta: {
                            vat_mode: "none",
                            vat_rate: "0.16",
                            tasa_dolar: "40",
                            base_currency: "USD",
                            cliente_id: cliente.id,
                            items: [
                              {
                                item_type: "product",
                                product_id: @product.id,
                                variation_id: @variation.id,
                                quantity: "1",
                                unit_price_usd: @product.precio_venta_usd.to_s,
                              },
                            ],
                            payments: [],
                            credit_sale: {
                              enabled: true,
                            },
                          },
                        }, as: :json
      end
    end

    assert_response :created

    sale = Venta.where(status: "paid").order(:id).last
    debt = Debt.order(:id).last

    assert_equal 0, sale.venta_payments.count
    assert_equal BigDecimal("10.0"), debt.amount.to_d
    assert_includes debt.description.to_s, "[VENTA:#{sale.id}]"
  end

  test "create requires payment date for bank account payments" do
    bank_account = @business.accounts.create!(
      name: "Banco VES Ventas",
      account_type: "bank_account",
      currency: "VES",
      balance: 50_000,
      active: true,
      theme_color: "sky",
      is_primary: true,
    )

    post "/ventas", params: {
                      venta: {
                        vat_mode: "none",
                        vat_rate: "0.16",
                        tasa_dolar: "40",
                        base_currency: "USD",
                        items: [
                          {
                            item_type: "product",
                            product_id: @product.id,
                            variation_id: @variation.id,
                            quantity: "1",
                            unit_price_usd: @product.precio_venta_usd.to_s,
                          },
                        ],
                        payments: [
                          {
                            method: "transfer",
                            amount: "400.00",
                            account_id: bank_account.id,
                            currency: "VES",
                            reference: "123456",
                          },
                        ],
                      },
                    }, as: :json

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_match(/fecha del pago/i, payload.fetch("error"))
  end

  test "create rejects duplicated bank payment by account date and amount even with different reference" do
    bank_account = @business.accounts.create!(
      name: "Banco VES Ventas",
      account_type: "bank_account",
      currency: "VES",
      balance: 50_000,
      active: true,
      theme_color: "sky",
      is_primary: true,
    )

    duplicated_date = Date.current
    existing_sale = create_paid_sale!(created_at: Time.zone.now.change(hour: 9), cash_shift: @open_cash_shift)
    existing_sale.venta_payments.create!(
      payment_method: "transfer",
      account: bank_account,
      amount_usd: 10,
      amount_original: 400,
      currency: "VES",
      reference: "123456",
      payment_kind: "in",
      payment_date: duplicated_date,
    )

    post "/ventas", params: {
                      venta: {
                        vat_mode: "none",
                        vat_rate: "0.16",
                        tasa_dolar: "40",
                        base_currency: "USD",
                        items: [
                          {
                            item_type: "product",
                            product_id: @product.id,
                            variation_id: @variation.id,
                            quantity: "1",
                            unit_price_usd: @product.precio_venta_usd.to_s,
                          },
                        ],
                        payments: [
                          {
                            method: "mobile",
                            amount: "400.00",
                            account_id: bank_account.id,
                            currency: "VES",
                            reference: "654321",
                            payment_date: duplicated_date.iso8601,
                          },
                        ],
                      },
                    }, as: :json

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_match(/Ya existe un pago registrado/i, payload.fetch("error"))

    duplicate_payload = payload.fetch("duplicate_payment")
    assert_equal existing_sale.id, duplicate_payload.fetch("venta_id")
    assert_equal BigDecimal("400.0"), duplicate_payload.fetch("amount").to_d
    assert_equal "VES", duplicate_payload.fetch("currency")
    assert_equal duplicated_date.strftime("%d/%m/%Y"), duplicate_payload.fetch("payment_date")
    assert_equal venta_path(existing_sale), duplicate_payload.fetch("venta_url")
  end

  test "historial shows full range when no date filter is provided" do
    today_sale = create_paid_sale!(created_at: Time.zone.now.change(hour: 11), cash_shift: @open_cash_shift)
    previous_day_sale = create_paid_sale!(created_at: Time.zone.now.change(hour: 11) - 1.day,
                                          cash_shift: @open_cash_shift)

    get historial_ventas_path

    assert_response :success
    assert_includes response.body, "Venta ##{today_sale.id}"
    assert_includes response.body, "Venta ##{previous_day_sale.id}"
  end

  test "historial filters sales by selected shift" do
    closed_shift = @business.cash_shifts.create!(
      opened_by: @user,
      closed_by: @user,
      status: "closed",
      opened_at: Time.zone.now - 2.days,
      closed_at: Time.zone.now - 2.days + 8.hours,
      opening_balance_ves: 0,
      opening_balance_usd: 0,
    )

    sale_in_open_shift = create_paid_sale!(created_at: Time.zone.now - 2.days, cash_shift: @open_cash_shift)
    sale_in_closed_shift = create_paid_sale!(created_at: Time.zone.now - 2.days, cash_shift: closed_shift)

    get historial_ventas_path, params: { cash_shift_id: closed_shift.id }

    assert_response :success
    assert_includes response.body, "Venta ##{sale_in_closed_shift.id}"
    refute_includes response.body, "Venta ##{sale_in_open_shift.id}"
  end

  test "historial filters by date range using same day" do
    target_date = Date.new(2026, 3, 1)
    matching_sale = create_paid_sale!(created_at: Time.zone.local(2026, 3, 1, 9, 0, 0), cash_shift: @open_cash_shift)
    other_sale = create_paid_sale!(created_at: Time.zone.local(2026, 3, 2, 9, 0, 0), cash_shift: @open_cash_shift)

    get historial_ventas_path, params: { fecha_desde: target_date.iso8601, fecha_hasta: target_date.iso8601 }

    assert_response :success
    assert_includes response.body, "Venta ##{matching_sale.id}"
    refute_includes response.body, "Venta ##{other_sale.id}"
  end

  test "historial accepts datepicker format dd-mm-yyyy on date range filters" do
    matching_sale = create_paid_sale!(created_at: Time.zone.local(2026, 3, 12, 10, 0, 0), cash_shift: @open_cash_shift)
    other_sale = create_paid_sale!(created_at: Time.zone.local(2026, 3, 13, 10, 0, 0), cash_shift: @open_cash_shift)

    get historial_ventas_path, params: { fecha_desde: "12-03-2026", fecha_hasta: "12-03-2026" }

    assert_response :success
    assert_includes response.body, "Venta ##{matching_sale.id}"
    refute_includes response.body, "Venta ##{other_sale.id}"
  end

  test "historial filters by date range" do
    outside_before = create_paid_sale!(created_at: Time.zone.local(2026, 3, 5, 9, 0, 0), cash_shift: @open_cash_shift)
    inside = create_paid_sale!(created_at: Time.zone.local(2026, 3, 10, 12, 0, 0), cash_shift: @open_cash_shift)
    outside_after = create_paid_sale!(created_at: Time.zone.local(2026, 3, 18, 12, 0, 0), cash_shift: @open_cash_shift)

    get historial_ventas_path, params: {
                                 fecha_desde: "2026-03-09",
                                 fecha_hasta: "2026-03-12",
                               }

    assert_response :success
    assert_includes response.body, "Venta ##{inside.id}"
    refute_includes response.body, "Venta ##{outside_before.id}"
    refute_includes response.body, "Venta ##{outside_after.id}"
  end

  test "historial summary cards include full filtered scope beyond first endless page" do
    25.times do |index|
      create_paid_sale!(created_at: Time.zone.now.change(hour: 10) + index.seconds, cash_shift: @open_cash_shift)
    end

    get historial_ventas_path

    assert_response :success
    assert_includes response.body, "25 resultados"
  end

  test "historial totals use each sale stored base rate instead of day rate" do
    sale_date = Time.zone.local(2026, 3, 21, 10, 0, 0)
    create_paid_sale!(
      created_at: sale_date,
      cash_shift: @open_cash_shift,
      base_currency: "USD",
      total_usd: 10,
      total_bs: 400,
      tasa_dolar: 40,
    )
    create_paid_sale!(
      created_at: sale_date + 1.hour,
      cash_shift: @open_cash_shift,
      base_currency: "USD",
      total_usd: 10,
      total_bs: 500,
      tasa_dolar: 50,
    )

    TasaCambio.create!(description: "Dolar BCV", valor: 70, fecha_referencia: sale_date.to_date)

    get historial_ventas_path, params: {
                                 fecha_desde: sale_date.to_date.iso8601,
                                 fecha_hasta: sale_date.to_date.iso8601,
                               }

    assert_response :success
    assert_match(/\$(?:\s|\u00A0)20,00/, response.body)
    assert_match(/Bs(?:\s|\u00A0)+900,00/, response.body)
    refute_match(/Bs(?:\s|\u00A0)+1\.400,00/, response.body)
  end

  test "show uses sale stored rate for equivalent amount" do
    sale_date = Time.zone.local(2026, 3, 22, 11, 0, 0)
    sale = create_paid_sale!(
      created_at: sale_date,
      cash_shift: @open_cash_shift,
      base_currency: "USD",
      total_usd: 10,
      total_bs: 400,
      tasa_dolar: 40,
    )

    TasaCambio.create!(description: "Dolar BCV", valor: 70, fecha_referencia: sale_date.to_date)

    get venta_path(sale)

    assert_response :success
    assert_match(/\$(?:\s|\u00A0)10,00/, response.body)
    assert_match(/Bs(?:\s|\u00A0)+400,00/, response.body)
    refute_match(/Bs(?:\s|\u00A0)+700,00/, response.body)
  end

  test "show renders service consumables and nested services as child invoice rows" do
    sale = create_paid_sale!(
      created_at: Time.zone.local(2026, 3, 23, 10, 0, 0),
      cash_shift: @open_cash_shift,
      base_currency: "USD",
      total_usd: 40,
      total_bs: 1_600,
      tasa_dolar: 40,
    )

    service_name = "Servicio Principal #{SecureRandom.hex(3)}"
    sale.venta_items.create!(
      product_name: service_name,
      variation_name: "INTT",
      quantity: 1,
      unit_price_usd: 40,
      subtotal_usd: 40,
    )

    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_name" => service_name,
            "detail_lines" => [
              {
                "classification" => "product_expense",
                "source_name" => "Adaptador Bluetooth (Azul)",
                "quantity" => 1,
                "amount_usd" => 6,
              },
              {
                "classification" => "nested_expense",
                "source_name" => "Servicio tecnico anidado",
                "quantity" => 1,
                "amount_usd" => 4,
              },
            ],
          },
        ],
      }.to_json,
    )

    get venta_path(sale)

    assert_response :success
    assert_includes response.body, "Adaptador Bluetooth (Azul)"
    assert_includes response.body, "Servicio tecnico anidado"
    assert_includes response.body, "Producto del servicio"
    assert_includes response.body, "Servicio anidado"
    assert_includes response.body, "Asociado a"
    refute_includes response.body, "Consumos descontados del servicio"
    assert_match(/\$(?:\s|\u00A0)30,00/, response.body)
  end

  test "show masks restricted and caution service names for non admin users" do
    staff_user = users(:maria)
    staff_user.update!(business: @business, admin: false, authorization_level: "standard_staff", active: true)

    caution_system = SystemService.create!(name: "Sistema Precaucion #{SecureRandom.hex(3)}")
    restricted_system = SystemService.create!(name: "Sistema Restringido #{SecureRandom.hex(3)}")

    caution_service = @business.services.create!(
      description: "Servicio Precaucion #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      available: true,
      caution_service: true,
      system_service: caution_system,
    )
    restricted_service = @business.services.create!(
      description: "Servicio Restringido #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      available: true,
      restricted_service: true,
      system_service: restricted_system,
    )

    sale = create_paid_sale!(created_at: Time.zone.now.change(hour: 13), cash_shift: @open_cash_shift)
    sale.venta_items.create!(
      product_name: caution_service.description,
      variation_name: caution_system.name,
      quantity: 1,
      unit_price_usd: 10,
      subtotal_usd: 10,
    )
    sale.venta_items.create!(
      product_name: restricted_service.description,
      variation_name: restricted_system.name,
      quantity: 1,
      unit_price_usd: 10,
      subtotal_usd: 10,
    )
    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_name" => caution_service.description,
            "detail_lines" => [
              {
                "classification" => "product_expense",
                "source_name" => "Consumible demo",
                "quantity" => 1,
                "amount_usd" => 1,
              },
            ],
          },
        ],
      }.to_json,
    )

    delete logout_path
    login_as!(user: staff_user, password: "testme")

    get venta_path(sale)

    assert_response :success
    assert_includes response.body, "Servicio de internet"
    assert_includes response.body, "Asociado a Servicio de internet"
    refute_includes response.body, caution_service.description
    refute_includes response.body, restricted_service.description
  end

  test "show keeps service name for admin users" do
    system_service = SystemService.create!(name: "Sistema Admin #{SecureRandom.hex(3)}")
    restricted_service = @business.services.create!(
      description: "Servicio Visible Admin #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      available: true,
      restricted_service: true,
      system_service: system_service,
    )

    sale = create_paid_sale!(created_at: Time.zone.now.change(hour: 14), cash_shift: @open_cash_shift)
    sale.venta_items.create!(
      product_name: restricted_service.description,
      variation_name: system_service.name,
      quantity: 1,
      unit_price_usd: 10,
      subtotal_usd: 10,
    )
    sale.update!(
      notes: {
        "service_cost_settlements" => [
          {
            "service_name" => restricted_service.description,
            "detail_lines" => [
              {
                "classification" => "nested_expense",
                "source_name" => "Anidado demo",
                "quantity" => 1,
                "amount_usd" => 2,
              },
            ],
          },
        ],
      }.to_json,
    )

    get venta_path(sale)

    assert_response :success
    assert_includes response.body, restricted_service.description
    assert_includes response.body, "Asociado a #{restricted_service.description}"
  end

  test "historial filters sales by cliente query" do
    matching_cliente = @business.clientes.create!(
      name: "Ana Morales",
      document_type: "V",
      document_number: "12345678",
    )
    other_cliente = @business.clientes.create!(
      name: "Carlos Rojas",
      document_type: "V",
      document_number: "87654321",
    )

    matching_sale = create_paid_sale!(
      created_at: Time.zone.now.change(hour: 14),
      cash_shift: @open_cash_shift,
      cliente: matching_cliente,
    )
    other_sale = create_paid_sale!(
      created_at: Time.zone.now.change(hour: 15),
      cash_shift: @open_cash_shift,
      cliente: other_cliente,
    )

    get historial_ventas_path, params: { cliente_query: "ana" }

    assert_response :success
    assert_includes response.body, "Venta ##{matching_sale.id}"
    refute_includes response.body, "Venta ##{other_sale.id}"
  end

  test "service with auto cost discount creates payable pending debt when cost is not paid immediately" do
    service = create_auto_cost_service!(service_price_usd: 20, cost_units: 1)

    assert_difference('Venta.where(status: "paid").count', 1) do
      assert_difference("Debt.where(service_cost_pending: true).count", 1) do
        post "/ventas", params: {
                          venta: {
                            vat_mode: "none",
                            vat_rate: "0.16",
                            tasa_dolar: "40",
                            base_currency: "USD",
                            items: [
                              {
                                item_type: "service",
                                service_id: service.id,
                                quantity: "1",
                                unit_price_usd: "20",
                              },
                            ],
                            payments: [
                              {
                                method: "cash",
                                amount: "800.00",
                                account_id: @cash_account.id,
                                currency: "VES",
                              },
                            ],
                          },
                        }, as: :json
      end
    end

    assert_response :created

    debt = Debt.where(service_cost_pending: true).order(:id).last

    assert_equal "payable", debt.debt_kind
    assert_equal service.id, debt.service_id
    assert_equal BigDecimal("10.0"), debt.amount.to_d
    assert_equal BigDecimal("10.0"), debt.balance.to_d
    assert_equal 9.to_d, stock_remaining_units
  end

  test "service with auto cost discount and inactive structures does not register service cost" do
    service = @business.services.create!(
      description: "Servicio sin estructura activa #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      sale_price: 20,
      available: true,
      cost: true,
      auto_cost_stock_discount: true,
    )
    structure = service.service_expense_structures.create!(description: "Costo inactivo", active_for_sales: false)
    structure.service_product_expenses.create!(producto: @product, quantity: 1)

    assert_difference('Venta.where(status: "paid").count', 1) do
      assert_no_difference("Debt.where(service_cost_pending: true).count") do
        post "/ventas", params: {
                          venta: {
                            vat_mode: "none",
                            vat_rate: "0.16",
                            tasa_dolar: "40",
                            base_currency: "USD",
                            items: [
                              {
                                item_type: "service",
                                service_id: service.id,
                                quantity: "1",
                                unit_price_usd: "20",
                              },
                            ],
                            payments: [
                              {
                                method: "cash",
                                amount: "800.00",
                                account_id: @cash_account.id,
                                currency: "VES",
                              },
                            ],
                          },
                        }, as: :json
      end
    end

    assert_response :created

    sale = Venta.where(status: "paid").order(:id).last
    notes_payload = sale.notes.present? ? JSON.parse(sale.notes) : {}
    assert_equal [], Array(notes_payload["service_cost_settlements"])
    assert_equal 10.to_d, stock_remaining_units
  end

  test "activating a structure applies only to subsequent sales" do
    service = @business.services.create!(
      description: "Servicio activacion diferida #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      sale_price: 20,
      available: true,
      cost: true,
      auto_cost_stock_discount: true,
    )
    structure = service.service_expense_structures.create!(description: "Costo alterno", active_for_sales: false)
    structure.service_product_expenses.create!(producto: @product, quantity: 1)

    assert_no_difference("Debt.where(service_cost_pending: true).count") do
      post "/ventas", params: {
                        venta: {
                          vat_mode: "none",
                          vat_rate: "0.16",
                          tasa_dolar: "40",
                          base_currency: "USD",
                          items: [
                            {
                              item_type: "service",
                              service_id: service.id,
                              quantity: "1",
                              unit_price_usd: "20",
                            },
                          ],
                          payments: [
                            {
                              method: "cash",
                              amount: "800.00",
                              account_id: @cash_account.id,
                              currency: "VES",
                            },
                          ],
                        },
                      }, as: :json
    end
    assert_response :created

    first_sale = Venta.where(status: "paid").order(:id).last
    first_notes = first_sale.notes.present? ? JSON.parse(first_sale.notes) : {}
    assert_equal [], Array(first_notes["service_cost_settlements"])

    structure.update!(active_for_sales: true)

    assert_difference("Debt.where(service_cost_pending: true).count", 1) do
      post "/ventas", params: {
                        venta: {
                          vat_mode: "none",
                          vat_rate: "0.16",
                          tasa_dolar: "40",
                          base_currency: "USD",
                          items: [
                            {
                              item_type: "service",
                              service_id: service.id,
                              quantity: "1",
                              unit_price_usd: "20",
                            },
                          ],
                          payments: [
                            {
                              method: "cash",
                              amount: "800.00",
                              account_id: @cash_account.id,
                              currency: "VES",
                            },
                          ],
                        },
                      }, as: :json
    end

    assert_response :created
    second_sale = Venta.where(status: "paid").order(:id).last
    second_notes = second_sale.notes.present? ? JSON.parse(second_sale.notes) : {}
    assert_equal 1, Array(second_notes["service_cost_settlements"]).size
    assert_equal 9.to_d, stock_remaining_units
  end

  test "service with auto cost discount can register full immediate cost payment without pending debt" do
    service = create_auto_cost_service!(service_price_usd: 20, cost_units: 1)

    assert_difference('Venta.where(status: "paid").count', 1) do
      assert_no_difference("Debt.where(service_cost_pending: true).count") do
        post "/ventas", params: {
                          venta: {
                            vat_mode: "none",
                            vat_rate: "0.16",
                            tasa_dolar: "40",
                            base_currency: "USD",
                            items: [
                              {
                                item_type: "service",
                                service_id: service.id,
                                quantity: "1",
                                unit_price_usd: "20",
                              },
                            ],
                            payments: [
                              {
                                method: "cash",
                                amount: "800.00",
                                account_id: @cash_account.id,
                                currency: "VES",
                              },
                            ],
                            service_cost_payments: [
                              {
                                service_id: service.id,
                                pay_now: true,
                                account_id: @cash_account.id,
                                amount: "400.00",
                                currency: "VES",
                                payment_method: "cash",
                              },
                            ],
                          },
                        }, as: :json
      end
    end

    assert_response :created

    sale = Venta.where(status: "paid").order(:id).last
    service_cost_movements = @cash_account
      .account_movements
      .where("description LIKE ?", "%[SERVICE_COST]%")
      .where("description LIKE ?", "%[VENTA:#{sale.id}]%")

    assert_equal 1, service_cost_movements.count
    assert_equal "expense", service_cost_movements.first.movement_kind
    assert_equal BigDecimal("400.0"), service_cost_movements.first.amount.to_d
    assert_equal 9.to_d, stock_remaining_units
  end

  private

  def login_and_select_business!
    login_as!(user: @user, password: "215150603")
  end

  def login_as!(user:, password:)
    post sessions_path, params: { login: user.email, password: password }
    post select_business_path(@business) if user.admin? || user.manager?
  end

  def draft_payload(quantity:, draft_id: nil, draft_visibility: nil)
    payload = {
      vat_mode: "none",
      vat_rate: "0.16",
      tasa_dolar: "40",
      base_currency: "USD",
      items: [
        {
          item_type: "product",
          product_id: @product.id,
          variation_id: @variation.id,
          quantity: quantity.to_s,
          unit_price_usd: @product.precio_venta_usd.to_s,
        },
      ],
    }

    payload[:draft_id] = draft_id if draft_id.present?
    payload[:draft_visibility] = draft_visibility if draft_visibility.present?
    payload
  end

  def sale_payload(quantity:, draft_id:, paid_amount_ves:)
    {
      draft_id: draft_id,
      vat_mode: "none",
      vat_rate: "0.16",
      tasa_dolar: "40",
      base_currency: "USD",
      items: [
        {
          item_type: "product",
          product_id: @product.id,
          variation_id: @variation.id,
          quantity: quantity.to_s,
          unit_price_usd: @product.precio_venta_usd.to_s,
        },
      ],
      payments: [
        {
          method: "cash",
          amount: paid_amount_ves,
          account_id: @cash_account.id,
          currency: "VES",
        },
      ],
    }
  end

  def create_product_with_stock!(available_units:, sale_price_usd:)
    product = @business.productos.create!(
      descripcion: "Producto Ventas #{SecureRandom.hex(3)}",
      categoria: @categoria,
      precio_venta_usd: sale_price_usd,
      porcentaje_ganancia: 0,
    )

    variation = product.product_variations.order(:id).first ||
                product.product_variations.create!(description: "Unica", safety_stock: 0)

    invoice = @business.purchase_invoices.create!(
      supplier: @supplier,
      fecha_emision: Date.current,
      tasa_dolar: 40,
      numero: "FAC-VENTAS-#{SecureRandom.hex(3)}",
    )

    item = invoice.purchase_invoice_items.create!(
      producto: product,
      product_name: product.descripcion,
      costo_mayor: 5,
      costo_menor: 5,
      costo_mayor_bs: 200,
      cantidad: available_units,
      unid_x_pack: 1,
      exento: false,
    )

    product.stock_lots.destroy_all

    lot = product.stock_lots.create!(
      purchase_invoice_item: item,
      supplier: @supplier,
      supplier_name: @supplier.nombre,
      unit_cost_usd: 5,
      quantity_in: available_units,
      quantity_remaining: available_units,
      purchased_at: Time.current,
    )

    lot.stock_lot_variations.create!(
      product_variation: variation,
      variation_description: variation.description,
      quantity_in: available_units,
      quantity_remaining: available_units,
    )
    lot.sync_quantity_remaining_from_variations!

    [product, variation]
  end

  def create_auto_cost_service!(service_price_usd:, cost_units:)
    service = @business.services.create!(
      description: "Servicio Auto #{SecureRandom.hex(3)}",
      pricing_mode: "to_agree",
      currency_base_price: "Dolar BCV",
      sale_price: service_price_usd,
      available: true,
      cost: true,
      auto_cost_stock_discount: false,
    )

    structure = service.service_expense_structures.create!(description: "Costo base", active_for_sales: true)
    structure.service_product_expenses.create!(producto: @product, quantity: cost_units)
    service.update!(auto_cost_stock_discount: true)
    service
  end

  def stock_remaining_units
    StockLotVariation
      .joins(:stock_lot)
      .where(stock_lots: { producto_id: @product.id }, product_variation_id: @variation.id)
      .sum(:quantity_remaining)
      .to_d
      .round(2)
  end

  def create_paid_sale!(created_at:, cash_shift:, cliente: nil, base_currency: "USD", total_usd: 10, total_bs: 400,
                        tasa_dolar: 40)
    sale = @business.ventas.create!(
      status: "paid",
      vat_mode: "none",
      vat_rate: 0.16,
      base_currency: base_currency,
      tasa_dolar: tasa_dolar,
      cliente: cliente,
      cash_shift: cash_shift,
      user: @user,
    )

    sale.update_columns(
      subtotal_usd: total_usd.to_d,
      vat_usd: 0.to_d,
      total_usd: total_usd.to_d,
      total_bs: total_bs.to_d,
      created_at: created_at,
      updated_at: created_at,
    )

    sale
  end
end
