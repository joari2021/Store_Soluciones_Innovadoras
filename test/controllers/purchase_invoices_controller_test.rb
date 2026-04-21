require 'test_helper'
require 'securerandom'

class PurchaseInvoicesControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ['users']
  fixtures :users

  setup do
    @user = users(:jorge)
    @business = Business.create!(name: "Negocio Test #{SecureRandom.hex(4)}")
    @supplier = @business.suppliers.create!(nombre: 'Proveedor Test')
    @categoria = @business.categorias.create!(nombre: "Categoria Test #{SecureRandom.hex(3)}")
    @producto = @business.productos.create!(
      descripcion: "Producto Factura #{SecureRandom.hex(3)}",
      categoria: @categoria,
      precio_venta_usd: 12
    )
    @bs_account = @business.accounts.create!(
      name: 'Caja Bs',
      account_type: 'cash_box',
      currency: 'VES',
      balance: 500,
      active: true,
      theme_color: 'sky'
    )

    login_and_select_business!
  end

  test 'creates invoice with full payment without pending debt' do
    assert_difference('PurchaseInvoice.count', 1) do
      assert_difference('AccountMovement.count', 1) do
        assert_no_difference('Debt.count') do
          post purchase_invoices_path, params: purchase_invoice_payload(
            payment_amount: '116.00',
            mark_pending_payment: '0'
          )
        end
      end
    end

    assert_redirected_to purchase_invoices_path

    invoice = PurchaseInvoice.order(:id).last
    movement = AccountMovement.order(:id).last

    assert_equal @bs_account.id, movement.account_id
    assert_equal 'expense', movement.movement_kind
    assert_equal BigDecimal('116.00'), movement.amount
    assert_includes movement.description, "[FACTURA_COMPRA:#{invoice.id}]"
  end

  test 'creates pending payable debt when invoice is partially paid' do
    due_date = Date.current + 5.days

    assert_difference('PurchaseInvoice.count', 1) do
      assert_difference('AccountMovement.count', 1) do
        assert_difference('Debt.count', 1) do
          post purchase_invoices_path, params: purchase_invoice_payload(
            payment_amount: '50.00',
            mark_pending_payment: '1',
            pending_due_on: due_date.strftime('%d-%m-%Y')
          )
        end
      end
    end

    assert_redirected_to purchase_invoices_path

    debt = Debt.order(:id).last
    assert_equal @business.id, debt.business_id
    assert_equal 'payable', debt.debt_kind
    assert_equal 'USD', debt.currency
    assert_equal due_date, debt.due_on
    assert_equal BigDecimal('6.60'), debt.amount
    assert_includes debt.description, 'Saldo pendiente factura'
    assert_includes debt.description, '[FACTURA_COMPRA:'
  end

  test 'updates pending debt in usd when editing normal purchase invoice totals' do
    due_date = Date.current + 5.days

    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '50.00',
      mark_pending_payment: '1',
      pending_due_on: due_date.strftime('%d-%m-%Y')
    )

    invoice = PurchaseInvoice.order(:id).last
    item = invoice.purchase_invoice_items.first
    debt = @business.debts.where('description LIKE ?', "%[FACTURA_COMPRA:#{invoice.id}]%").order(created_at: :desc).first

    assert_not_nil debt
    assert_equal BigDecimal('6.60'), debt.amount.to_d
    assert_equal 'USD', debt.currency

    patch purchase_invoice_path(invoice), params: {
      purchase_invoice: {
        supplier_id: @supplier.id,
        fecha_emision: invoice.fecha_emision,
        tasa_dolar: '10',
        numero: invoice.numero,
        purchase_invoice_items_attributes: {
          '0' => {
            id: item.id,
            _destroy: '0',
            producto_id: @producto.id,
            product_name: item.product_name,
            cantidad: '1',
            unid_x_pack: '1',
            costo_mayor: '20',
            costo_mayor_bs: '200',
            costo_menor: '20',
            exento: '0'
          }
        }
      }
    }

    assert_redirected_to purchase_invoices_path

    debt.reload
    assert_equal 'USD', debt.currency
    assert_equal BigDecimal('18.20'), debt.amount.to_d
  end

  test 'shows payment summary in edit invoice view' do
    due_date = Date.current + 5.days

    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '50.00',
      mark_pending_payment: '1',
      pending_due_on: due_date.strftime('%d-%m-%Y')
    )

    invoice = PurchaseInvoice.order(:id).last

    get edit_purchase_invoice_path(invoice)

    assert_response :success
    assert_includes response.body, 'Pago de factura'
    assert_includes response.body, 'Caja Bs'
    assert_includes response.body, 'Ver deuda'
    assert_includes response.body, 'Registrar pago'
    assert_includes response.body, 'Saldo pendiente actual Bs'
  end

  test 'shows payment method and debt allocation in invoice show view' do
    bank_account = @business.accounts.create!(
      name: 'Banco Bs',
      account_type: 'bank_account',
      currency: 'VES',
      balance: 500,
      active: true,
      theme_color: 'emerald'
    )
    due_date = Date.current + 5.days

    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '50.00',
      mark_pending_payment: '1',
      pending_due_on: due_date.strftime('%d-%m-%Y'),
      account_id: bank_account.id
    )

    invoice = PurchaseInvoice.order(:id).last

    get purchase_invoice_path(invoice)

    assert_response :success
    assert_includes response.body, 'Pago de factura'
    assert_includes response.body, 'Métodos de pago registrados'
    assert_includes response.body, 'Transferencia'
    assert_includes response.body, 'Asignado a deuda $'
    assert_includes response.body, 'Saldo pendiente actual $'
    assert_includes response.body, 'Base: total factura'
    assert_includes response.body, '6,60'

    items_index = response.body.index('Items de la factura')
    payment_index = response.body.index('Pago de factura')
    assert items_index.present?
    assert payment_index.present?
    assert_operator items_index, :<, payment_index
  end

  test 'hides register payment button in show when invoice debt is fully paid' do
    invoice = create_invoice_with_payment_status(paid_amount_bs: 50, pending_debt_amount_bs: 66)
    debt = @business.debts.where('description LIKE ?',
                                 "%[FACTURA_COMPRA:#{invoice.id}]%").order(created_at: :desc).first

    DebtPayment.create!(
      debt: debt,
      account: @bs_account,
      amount: debt.amount,
      occurred_at: Date.current
    )

    get purchase_invoice_path(invoice)

    assert_response :success
    refute_includes response.body, 'Registrar pago'
    assert_includes response.body, 'Ver deuda'
    assert_includes response.body, 'Estado: Pagada'
  end

  test 'renders costo mayor bs formatted correctly in invoice edit form' do
    bs_supplier = @business.suppliers.create!(
      nombre: 'Proveedor Bs',
      pricing_currency_priority: 'bs'
    )

    invoice = @business.purchase_invoices.new(
      supplier: bs_supplier,
      fecha_emision: Date.current,
      tasa_dolar: 10,
      numero: "FAC-#{SecureRandom.hex(3)}"
    )
    invoice.purchase_invoice_items.build(
      product_name: 'Producto Bs',
      costo_mayor: 123.456,
      costo_mayor_bs: 1234.56,
      cantidad: 1,
      unid_x_pack: 1,
      exento: false
    )
    invoice.save!

    get edit_purchase_invoice_path(invoice)

    assert_response :success
    assert_select 'input.row-costo-mayor-bs-native[value="1234.56"]', 1
    assert_select 'input.row-costo-mayor-bs[data-money-symbol="Bs"]'
    assert_includes response.body, '1.234,56'
  end

  test 'rejects invoice when selected account has insufficient balance' do
    @bs_account.update!(balance: 20)

    assert_no_difference('PurchaseInvoice.count') do
      assert_no_difference('AccountMovement.count') do
        assert_no_difference('Debt.count') do
          post purchase_invoices_path, params: purchase_invoice_payload(
            payment_amount: '116.00',
            mark_pending_payment: '0'
          )
        end
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body.downcase, 'saldo insuficiente'
  end

  test 'shows payment status column and filter selector in invoices index' do
    create_invoice_with_payment_status(paid_amount_bs: 50, pending_debt_amount_bs: 66)

    get purchase_invoices_path

    assert_response :success
    assert_includes response.body, 'Estado de pago'
    assert_select 'select[name="payment_status"] option[value="paid"]', text: 'Pagada'
    assert_select 'select[name="payment_status"] option[value="partial"]', text: 'Parcialmente pagada'
    assert_select 'select[name="payment_status"] option[value="due"]', text: 'Se debe'
    assert_select '[data-invoice-status="partial"]', minimum: 1

    status_index = response.body.index('Estado de pago')
    actions_index = response.body.index('Acciones')
    assert status_index.present?
    assert actions_index.present?
    assert_operator status_index, :<, actions_index
  end

  test 'filters invoices by selected payment status in index' do
    create_invoice_with_payment_status(paid_amount_bs: 116, pending_debt_amount_bs: 0)
    create_invoice_with_payment_status(paid_amount_bs: 50, pending_debt_amount_bs: 66)
    create_invoice_with_payment_status(paid_amount_bs: 0, pending_debt_amount_bs: 116)

    get purchase_invoices_path, params: { payment_status: 'partial' }

    assert_response :success
    assert_select '[data-invoice-status="partial"]', minimum: 1
    assert_select '[data-invoice-status="paid"]', 0
    assert_select '[data-invoice-status="due"]', 0
  end

  test 'shows delivery status filter selector in invoices index' do
    create_invoice_with_payment_status(paid_amount_bs: 116, pending_debt_amount_bs: 0, delivered: true)

    get purchase_invoices_path

    assert_response :success
    assert_includes response.body, 'Estado de entrega'
    assert_select 'select[name="delivery_status"] option[value="delivered"]', text: 'Entregada'
    assert_select 'select[name="delivery_status"] option[value="not_delivered"]', text: 'No entregada'
  end

  test 'filters invoices by selected delivery status in index' do
    create_invoice_with_payment_status(paid_amount_bs: 116, pending_debt_amount_bs: 0, delivered: true)
    create_invoice_with_payment_status(paid_amount_bs: 116, pending_debt_amount_bs: 0, delivered: false)

    get purchase_invoices_path, params: { delivery_status: 'not_delivered' }

    assert_response :success
    assert_select 'span', text: 'No entregada', minimum: 1
    assert_select 'span', text: 'Entregada', count: 0
  end

  test 'destroy removes linked debt payments account movements and stock lots' do
    due_date = Date.current + 5.days

    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '50.00',
      mark_pending_payment: '1',
      pending_due_on: due_date.strftime('%d-%m-%Y'),
      product_id: @producto.id,
      quantity: '2'
    )

    assert_redirected_to purchase_invoices_path

    invoice = PurchaseInvoice.order(:id).last
    invoice_tag = "[FACTURA_COMPRA:#{invoice.id}]"
    linked_debt = @business.debts.where('description LIKE ?', "%#{invoice_tag}%").order(:id).last
    item_ids = invoice.purchase_invoice_items.pluck(:id)

    assert linked_debt.present?
    assert StockLot.where(factura_item_id: item_ids).exists?
    assert_operator @producto.reload.total_quantity.to_d, :>, 0.to_d

    TasaCambio.find_or_create_by!(description: 'Dolar BCV', fecha_referencia: Date.current) do |rate|
      rate.valor = 10
    end

    DebtPayment.create!(
      debt: linked_debt,
      account: @bs_account,
      amount: 10,
      occurred_at: Date.current
    )

    tagged_movements_scope = AccountMovement.joins(:account)
                                            .where(accounts: { business_id: @business.id })
                                            .where('account_movements.description LIKE ?', "%#{invoice_tag}%")

    assert tagged_movements_scope.exists?

    assert_difference('PurchaseInvoice.count', -1) do
      assert_difference('Debt.count', -1) do
        assert_difference('DebtPayment.count', -1) do
          delete purchase_invoice_path(invoice)
        end
      end
    end

    assert_redirected_to purchase_invoices_path
    assert_equal 0, StockLot.where(factura_item_id: item_ids).count
    assert_equal 0, @business.debts.where('description LIKE ?', "%#{invoice_tag}%").count
    assert_equal 0, tagged_movements_scope.count
    assert_equal 0.to_d, @producto.reload.total_quantity.to_d
  end

  test 'auto assigns single variation quantities in units for purchase lots' do
    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '232.00',
      mark_pending_payment: '0',
      product_id: @producto.id,
      quantity: '2',
      units_per_pack: '4'
    )

    assert_redirected_to purchase_invoices_path

    item = PurchaseInvoiceItem.order(:id).last
    variation = @producto.product_variations.order(:id).first
    breakdown_row = item.variation_breakdown.first

    assert_equal 1, item.variation_breakdown.size
    assert_equal variation.id, breakdown_row['variation_id']
    assert_equal variation.description, breakdown_row['description']
    assert_equal BigDecimal('8'), breakdown_row['quantity'].to_d

    lot_variation = item.stock_lot.stock_lot_variations.order(:id).first
    assert_not_nil lot_variation
    assert_equal variation.id, lot_variation.product_variation_id
    assert_equal BigDecimal('8'), lot_variation.quantity_in.to_d
    assert_equal BigDecimal('8'), lot_variation.quantity_remaining.to_d
  end

  test 'does not create stock lots when invoice is saved as not delivered' do
    assert_difference('PurchaseInvoice.count', 1) do
      post purchase_invoices_path, params: purchase_invoice_payload(
        payment_amount: '232.00',
        mark_pending_payment: '0',
        product_id: @producto.id,
        quantity: '2',
        delivered: '0'
      )
    end

    assert_redirected_to purchase_invoices_path

    invoice = PurchaseInvoice.order(:id).last
    item_ids = invoice.purchase_invoice_items.pluck(:id)

    assert_equal false, invoice.stock_delivered?
    assert_equal 0, StockLot.where(factura_item_id: item_ids).count
    assert_equal 0.to_d, @producto.reload.total_quantity.to_d
  end

  test 'applies stock when marking delivered and reverts when switching back to not delivered' do
    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '348.00',
      mark_pending_payment: '0',
      product_id: @producto.id,
      quantity: '3',
      delivered: '0'
    )

    invoice = PurchaseInvoice.order(:id).last
    item = invoice.purchase_invoice_items.first

    assert_equal 0.to_d, @producto.reload.total_quantity.to_d

    patch purchase_invoice_path(invoice), params: update_invoice_payload(invoice: invoice, item: item, delivered: '1')
    assert_redirected_to purchase_invoices_path

    assert_equal 3.to_d, @producto.reload.total_quantity.to_d
    assert_equal true, invoice.reload.stock_delivered?

    patch purchase_invoice_path(invoice), params: update_invoice_payload(invoice: invoice, item: item, delivered: '0')
    assert_redirected_to purchase_invoices_path

    assert_equal false, invoice.reload.stock_delivered?
    assert_equal 0.to_d, @producto.reload.total_quantity.to_d
    assert_equal 0, StockLot.where(factura_item_id: item.id).count
  end

  test 'rejects switching to not delivered when invoice stock was already consumed' do
    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '348.00',
      mark_pending_payment: '0',
      product_id: @producto.id,
      quantity: '3',
      delivered: '1'
    )

    invoice = PurchaseInvoice.order(:id).last
    item = invoice.purchase_invoice_items.first
    lot = item.stock_lot
    lot.update!(quantity_remaining: 2)

    patch purchase_invoice_path(invoice), params: update_invoice_payload(invoice: invoice, item: item, delivered: '0')

    assert_response :unprocessable_entity
    assert_includes response.body, 'no se puede cambiar a no entregada'
    assert_equal true, invoice.reload.stock_delivered?
    assert_equal 2.to_d, lot.reload.quantity_remaining.to_d
  end

  test 'show invoice renders current variation name after variation rename' do
    variation = @producto.product_variations.order(:id).first

    post purchase_invoices_path, params: purchase_invoice_payload(
      payment_amount: '232.00',
      mark_pending_payment: '0',
      product_id: @producto.id,
      quantity: '2',
      units_per_pack: '4',
      variation_breakdown: [{ variation_id: variation.id, description: 'Unica', quantity: 8 }]
    )

    invoice = PurchaseInvoice.order(:id).last
    variation.update!(description: 'Azul')

    get purchase_invoice_path(invoice)

    assert_response :success
    assert_includes response.body, 'Azul'
    refute_includes response.body, '>Unica</span>'
  end

  test 'intercompany not delivered does not alter source or destination stock' do
    source_business = Business.create!(name: "Origen Test #{SecureRandom.hex(4)}")
    source_supplier = source_business.suppliers.create!(nombre: 'Proveedor Origen')
    source_category = source_business.categorias.create!(nombre: "Categoria Origen #{SecureRandom.hex(3)}")
    source_product = source_business.productos.create!(
      descripcion: "Producto Origen #{SecureRandom.hex(3)}",
      categoria: source_category,
      precio_venta_usd: 8
    )
    source_variation = source_product.product_variations.order(:id).first

    source_invoice = source_business.purchase_invoices.create!(
      supplier: source_supplier,
      fecha_emision: Date.current,
      tasa_dolar: 10,
      numero: "SRC-#{SecureRandom.hex(3)}",
      delivered: true
    )
    source_invoice.purchase_invoice_items.create!(
      producto: source_product,
      product_name: source_product.descripcion,
      costo_mayor: 5,
      costo_mayor_bs: 50,
      cantidad: 10,
      unid_x_pack: 1,
      exento: false,
      variation_breakdown: [{ variation_id: source_variation.id, description: source_variation.description, quantity: 10 }]
    )

    source_stock_before = source_product.reload.total_quantity.to_d

    assert_difference('PurchaseInvoice.count', 1) do
      post purchase_invoices_path, params: {
        mode: 'intercompany',
        purchase_invoice: {
          intercompany: '1',
          source_business_id: source_business.id.to_s,
          fecha_emision: Date.current,
          tasa_dolar: '10',
          numero: "IC-#{SecureRandom.hex(3)}",
          delivered: '0',
          purchase_invoice_items_attributes: {
            '0' => {
              producto_id: source_product.id.to_s,
              product_name: source_product.descripcion,
              cantidad: '2',
              unid_x_pack: '2',
              costo_mayor: '0',
              exento: '1',
              variation_breakdown: [{ variation_id: source_variation.id, description: source_variation.description, quantity: 2 }]
            }
          }
        },
        mark_pending_payment: '1',
        pending_due_on: (Date.current + 5.days).strftime('%d-%m-%Y')
      }
    end

    assert_redirected_to purchase_invoices_path

    invoice = PurchaseInvoice.order(:id).last
    destination_item = invoice.purchase_invoice_items.first

    assert_equal false, invoice.stock_delivered?
    assert_equal source_stock_before, source_product.reload.total_quantity.to_d
    assert_nil destination_item.stock_lot
  end

  private

  def login_and_select_business!
    post sessions_path, params: { login: @user.email, password: '215150603' }
    post select_business_path(@business)
  end

  def purchase_invoice_payload(payment_amount:, mark_pending_payment:, pending_due_on: '', account_id: @bs_account.id,
                               product_id: nil, quantity: '1', units_per_pack: '1', variation_breakdown: nil,
                               delivered: '1')
    item_attributes = {
      product_name: 'Producto prueba',
      costo_mayor: '10',
      cantidad: quantity,
      unid_x_pack: units_per_pack,
      exento: '0'
    }
    item_attributes[:producto_id] = product_id.to_s if product_id.present?
    item_attributes[:variation_breakdown] = variation_breakdown if variation_breakdown.present?

    {
      purchase_invoice: {
        supplier_id: @supplier.id,
        fecha_emision: Date.current,
        tasa_dolar: '10',
        delivered: delivered,
        numero: "FAC-#{SecureRandom.hex(3)}",
        purchase_invoice_items_attributes: {
          '0' => item_attributes
        }
      },
      invoice_payments: {
        '0' => {
          account_id: account_id.to_s,
          amount: payment_amount
        }
      },
      mark_pending_payment: mark_pending_payment,
      pending_due_on: pending_due_on
    }
  end

  def update_invoice_payload(invoice:, item:, delivered:)
    {
      purchase_invoice: {
        supplier_id: @supplier.id,
        fecha_emision: invoice.fecha_emision,
        tasa_dolar: invoice.tasa_dolar.to_s,
        delivered: delivered,
        numero: invoice.numero,
        purchase_invoice_items_attributes: {
          '0' => {
            id: item.id,
            _destroy: '0',
            producto_id: item.producto_id,
            product_name: item.product_name,
            cantidad: item.cantidad.to_s,
            unid_x_pack: item.unid_x_pack.to_s,
            costo_mayor: item.costo_mayor.to_s,
            costo_mayor_bs: item.costo_mayor_bs.to_s,
            costo_menor: item.costo_menor.to_s,
            exento: item.exento? ? '1' : '0',
            variation_breakdown: item.variation_breakdown
          }
        }
      },
      mark_pending_payment: '0'
    }
  end

  def create_invoice_with_payment_status(paid_amount_bs:, pending_debt_amount_bs:, delivered: true)
    invoice = @business.purchase_invoices.new(
      supplier: @supplier,
      fecha_emision: Date.current,
      tasa_dolar: 10,
      delivered: delivered,
      numero: "FAC-#{SecureRandom.hex(3)}"
    )
    invoice.purchase_invoice_items.build(
      product_name: 'Producto prueba',
      costo_mayor: 10,
      cantidad: 1,
      unid_x_pack: 1,
      exento: false
    )
    invoice.save!

    if paid_amount_bs.to_d.positive?
      @bs_account.account_movements.create!(
        movement_kind: 'expense',
        amount: paid_amount_bs,
        description: "Pago factura compra #{invoice.numero} - #{@supplier.nombre} [FACTURA_COMPRA:#{invoice.id}]",
        occurred_at: invoice.fecha_emision
      )
    end

    return invoice unless pending_debt_amount_bs.to_d.positive?

    @business.debts.create!(
      debt_kind: 'payable',
      name: @supplier.nombre,
      description: "Saldo pendiente factura #{invoice.numero} - Proveedor: #{@supplier.nombre} [FACTURA_COMPRA:#{invoice.id}]",
      amount: pending_debt_amount_bs,
      currency: 'VES',
      issued_on: invoice.fecha_emision,
      due_on: invoice.fecha_emision + 5.days
    )

    invoice
  end
end
