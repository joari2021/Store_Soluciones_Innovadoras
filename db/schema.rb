# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_09_05_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "plpgsql"

  create_table "account_movements", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "movement_kind", null: false
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.text "description"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_method"
    t.bigint "account_settlement_id"
    t.bigint "cambio_efectivo_id"
    t.string "reference"
    t.decimal "commission_amount", precision: 14, scale: 2
    t.boolean "verified", default: false, null: false
    t.index ["account_id", "occurred_at"], name: "index_account_movements_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_account_movements_on_account_id"
    t.index ["account_settlement_id"], name: "index_account_movements_on_account_settlement_id"
    t.index ["cambio_efectivo_id"], name: "index_account_movements_on_cambio_efectivo_id"
    t.index ["movement_kind"], name: "index_account_movements_on_movement_kind"
    t.index ["payment_method"], name: "index_account_movements_on_payment_method"
    t.index ["reference"], name: "index_account_movements_on_reference"
    t.index ["verified"], name: "index_account_movements_on_verified"
  end

  create_table "account_settlements", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "settlement_account_id"
    t.decimal "total_amount", precision: 14, scale: 2, null: false
    t.integer "movements_count", default: 0, null: false
    t.datetime "closed_at", null: false
    t.datetime "period_start_at"
    t.datetime "period_end_at"
    t.decimal "credited_amount", precision: 14, scale: 2
    t.decimal "commission_amount", precision: 14, scale: 2
    t.datetime "processed_at"
    t.date "settlement_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "processed_at"], name: "index_account_settlements_on_account_id_and_processed_at"
    t.index ["account_id"], name: "index_account_settlements_on_account_id"
    t.index ["settlement_account_id"], name: "index_account_settlements_on_settlement_account_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "account_type", null: false
    t.string "currency", null: false
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "balance", precision: 14, scale: 2, default: "0.0", null: false
    t.string "theme_color", default: "sky", null: false
    t.bigint "business_id", null: false
    t.boolean "is_primary", default: false, null: false
    t.bigint "settlement_account_id"
    t.string "shared_key", null: false
    t.string "cash_role"
    t.string "cashea_line_mode", default: "cotidiana", null: false
    t.integer "cashea_cotidiana_installments", default: 1, null: false
    t.decimal "cashea_min_purchase_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "cashea_commission_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "cashea_principal_min_purchase_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.jsonb "cashea_cotidiana_category_ids", default: [], null: false
    t.index ["account_type"], name: "index_accounts_on_account_type"
    t.index ["active"], name: "index_accounts_on_active"
    t.index ["business_id"], name: "index_accounts_on_business_id"
    t.index ["business_id"], name: "index_accounts_primary_bank_per_business", unique: true, where: "(((account_type)::text = 'bank_account'::text) AND is_primary)"
    t.index ["cash_role"], name: "index_accounts_on_cash_role"
    t.index ["currency"], name: "index_accounts_on_currency"
    t.index ["settlement_account_id"], name: "index_accounts_on_settlement_account_id"
    t.index ["shared_key"], name: "index_accounts_on_shared_key"
    t.index ["theme_color"], name: "index_accounts_on_theme_color"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "animes", force: :cascade do |t|
    t.string "poster"
    t.string "name"
    t.integer "year"
    t.integer "temporadas"
    t.integer "capitulos"
    t.text "sinopsis"
    t.string "audio"
    t.string "calidad"
    t.string "formato_video"
    t.string "codigo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disponible", default: true
    t.string "link_trailer"
  end

  create_table "appointments", force: :cascade do |t|
    t.string "appointment_type", null: false
    t.datetime "appointment_date"
    t.string "appointment_time"
    t.string "status", default: "disponible", null: false
    t.boolean "reschedulable", default: true, null: false
    t.bigint "saime_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "client"
    t.index ["saime_user_id"], name: "index_appointments_on_saime_user_id"
  end

  create_table "business_user_assignments", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "user_id", null: false
    t.string "authorization_level", default: "standard_staff", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "customer_access_level", default: "none", null: false
    t.index ["business_id", "user_id"], name: "idx_business_user_assignments_unique", unique: true
    t.index ["business_id"], name: "index_business_user_assignments_on_business_id"
    t.index ["customer_access_level"], name: "index_business_user_assignments_on_customer_access_level"
    t.index ["user_id", "active"], name: "idx_business_user_assignments_user_active"
    t.index ["user_id"], name: "index_business_user_assignments_on_user_id"
  end

  create_table "businesses", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "theme_profile", default: "neon_blue", null: false
    t.boolean "hide_initial_inventory_button", default: false, null: false
    t.string "phone"
    t.text "address"
    t.string "rif"
    t.string "city"
    t.string "state"
    t.boolean "customer_pos_restrictions_enabled", default: true, null: false
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["theme_profile"], name: "index_businesses_on_theme_profile"
  end

  create_table "cambio_efectivos", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "user_id", null: false
    t.bigint "cash_shift_id"
    t.decimal "efectivo_vendido", precision: 12, scale: 2, null: false
    t.decimal "monto_caja_operativa", precision: 12, scale: 2, null: false
    t.decimal "monto_caja_deposito", precision: 12, scale: 2, null: false
    t.decimal "monto_recibido", precision: 12, scale: 2, null: false
    t.decimal "recargo_percent", precision: 5, scale: 2, null: false
    t.string "payment_group", null: false
    t.string "currency", default: "VES", null: false
    t.jsonb "payment_details", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_cambio_efectivos_on_business_id"
    t.index ["cash_shift_id"], name: "index_cambio_efectivos_on_cash_shift_id"
    t.index ["occurred_at"], name: "index_cambio_efectivos_on_occurred_at"
    t.index ["user_id"], name: "index_cambio_efectivos_on_user_id"
  end

  create_table "cash_shifts", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "opened_by_id", null: false
    t.bigint "closed_by_id"
    t.string "status", default: "open", null: false
    t.datetime "opened_at", null: false
    t.datetime "closed_at"
    t.decimal "opening_balance_ves", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "opening_balance_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "declared_closing_ves", precision: 14, scale: 2
    t.decimal "declared_closing_usd", precision: 14, scale: 2
    t.text "opening_notes"
    t.text "closing_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "active_cashier_id"
    t.index ["active_cashier_id"], name: "index_cash_shifts_on_active_cashier_id"
    t.index ["business_id", "status"], name: "index_cash_shifts_on_business_id_and_status"
    t.index ["business_id"], name: "index_cash_shifts_on_business_id"
    t.index ["closed_by_id"], name: "index_cash_shifts_on_closed_by_id"
    t.index ["opened_at"], name: "index_cash_shifts_on_opened_at"
    t.index ["opened_by_id"], name: "index_cash_shifts_on_opened_by_id"
  end

  create_table "categorias", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "nombre", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "nombre"], name: "index_categorias_on_business_id_and_nombre", unique: true
    t.index ["business_id"], name: "index_categorias_on_business_id"
  end

  create_table "clientes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "document_type", null: false
    t.string "document_number"
    t.string "name", null: false
    t.string "phone"
    t.text "address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "benefits_config", default: {}, null: false
    t.bigint "user_id"
    t.index ["business_id", "document_type", "document_number"], name: "index_clientes_on_business_doc"
    t.index ["business_id", "user_id"], name: "index_clientes_on_business_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["business_id"], name: "index_clientes_on_business_id"
    t.index ["name"], name: "index_clientes_on_name"
    t.index ["user_id"], name: "index_clientes_on_user_id"
  end

  create_table "debt_payments", force: :cascade do |t|
    t.bigint "debt_id", null: false
    t.bigint "account_id", null: false
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.string "currency", null: false
    t.string "payment_method"
    t.string "reference"
    t.date "occurred_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "exchange_rate_to_debt_currency", precision: 20, scale: 8, default: "1.0", null: false
    t.decimal "amount_in_debt_currency", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["account_id"], name: "index_debt_payments_on_account_id"
    t.index ["currency"], name: "index_debt_payments_on_currency"
    t.index ["debt_id"], name: "index_debt_payments_on_debt_id"
    t.index ["occurred_at"], name: "index_debt_payments_on_occurred_at"
  end

  create_table "debts", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "debt_kind", default: "receivable", null: false
    t.string "name", null: false
    t.text "description"
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.date "issued_on"
    t.date "due_on"
    t.bigint "cliente_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "service_cost_pending", default: false, null: false
    t.bigint "venta_id"
    t.bigint "service_id"
    t.jsonb "service_cost_details", default: {}, null: false
    t.bigint "mirror_debt_id"
    t.bigint "mirror_account_id"
    t.boolean "mirror_sync_enabled", default: false, null: false
    t.string "group_token"
    t.string "acreedor"
    t.index ["business_id", "debt_kind", "acreedor"], name: "index_debts_on_business_kind_acreedor"
    t.index ["business_id", "debt_kind", "group_token"], name: "idx_debts_group_token"
    t.index ["business_id"], name: "index_debts_on_business_id"
    t.index ["cliente_id"], name: "index_debts_on_cliente_id"
    t.index ["debt_kind"], name: "index_debts_on_debt_kind"
    t.index ["due_on"], name: "index_debts_on_due_on"
    t.index ["issued_on"], name: "index_debts_on_issued_on"
    t.index ["mirror_account_id"], name: "index_debts_on_mirror_account_id"
    t.index ["mirror_debt_id"], name: "index_debts_on_mirror_debt_id"
    t.index ["service_cost_pending", "debt_kind"], name: "index_debts_on_service_cost_pending_and_kind"
    t.index ["service_id"], name: "index_debts_on_service_id"
    t.index ["venta_id"], name: "index_debts_on_venta_id"
  end

  create_table "discount_schedules", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "name", default: "", null: false
    t.string "applies_to", default: "products", null: false
    t.jsonb "product_ids", default: [], null: false
    t.jsonb "service_ids", default: [], null: false
    t.string "quantity_mode", default: "from_quantity", null: false
    t.integer "quantity_threshold", default: 1, null: false
    t.string "discount_mode", default: "percent", null: false
    t.decimal "discount_value", precision: 12, scale: 2, null: false
    t.date "starts_on"
    t.date "ends_on"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "active"], name: "index_discount_schedules_on_business_id_and_active"
    t.index ["business_id"], name: "index_discount_schedules_on_business_id"
    t.index ["ends_on"], name: "index_discount_schedules_on_ends_on"
    t.index ["starts_on"], name: "index_discount_schedules_on_starts_on"
  end

  create_table "expense_categories", force: :cascade do |t|
    t.bigint "business_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_expense_categories_on_lower_name", unique: true
    t.index ["business_id"], name: "index_expense_categories_on_business_id"
  end

  create_table "expense_payments", force: :cascade do |t|
    t.bigint "expense_id", null: false
    t.bigint "account_id", null: false
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.string "currency", null: false
    t.string "payment_method"
    t.string "reference"
    t.datetime "occurred_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_expense_payments_on_account_id"
    t.index ["expense_id"], name: "index_expense_payments_on_expense_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "expense_type", default: "variable", null: false
    t.string "frequency", default: "once", null: false
    t.date "start_date"
    t.date "end_date"
    t.date "next_due_on"
    t.date "last_paid_on"
    t.integer "occurrences_limit"
    t.integer "payments_count", default: 0, null: false
    t.decimal "amount", precision: 14, scale: 2
    t.string "currency", default: "USD"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "expense_category_id"
    t.index ["business_id"], name: "index_expenses_on_business_id"
    t.index ["expense_category_id"], name: "index_expenses_on_expense_category_id"
  end

  create_table "factura_items", force: :cascade do |t|
    t.bigint "factura_id", null: false
    t.bigint "producto_id"
    t.decimal "costo_mayor", precision: 12, scale: 2
    t.decimal "cantidad", precision: 14, scale: 3, null: false
    t.decimal "costo_menor", precision: 12, scale: 2
    t.string "variacion_nombre"
    t.decimal "unid_x_pack", precision: 12, scale: 2
    t.decimal "subtotal", precision: 14, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_name"
    t.boolean "exento", default: false, null: false
    t.decimal "costo_mayor_bs", precision: 14, scale: 2
    t.jsonb "variation_breakdown", default: [], null: false
    t.index ["factura_id"], name: "index_factura_items_on_factura_id"
    t.index ["producto_id"], name: "index_factura_items_on_producto_id"
  end

  create_table "facturas", force: :cascade do |t|
    t.bigint "supplier_id"
    t.datetime "fecha_emision"
    t.decimal "tasa_dolar", precision: 12, scale: 2
    t.decimal "monto_total", precision: 14, scale: 2
    t.string "numero"
    t.text "observaciones"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "supplier_name"
    t.bigint "business_id", null: false
    t.string "invoice_kind", default: "purchase", null: false
    t.boolean "intercompany", default: false, null: false
    t.bigint "source_business_id"
    t.boolean "delivered", default: true, null: false
    t.decimal "descuento_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "descuento_bs", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["business_id"], name: "index_facturas_on_business_id"
    t.index ["business_id"], name: "index_facturas_unique_initial_inventory_per_business", unique: true, where: "((invoice_kind)::text = 'initial_inventory'::text)"
    t.index ["delivered"], name: "index_facturas_on_delivered"
    t.index ["invoice_kind"], name: "index_facturas_on_invoice_kind"
    t.index ["source_business_id"], name: "index_facturas_on_source_business_id"
  end

  create_table "generos", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "generos_animes", force: :cascade do |t|
    t.bigint "anime_id", null: false
    t.bigint "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["anime_id"], name: "index_generos_animes_on_anime_id"
    t.index ["genero_id"], name: "index_generos_animes_on_genero_id"
  end

  create_table "generos_juegos", force: :cascade do |t|
    t.bigint "juego_id", null: false
    t.bigint "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["genero_id"], name: "index_generos_juegos_on_genero_id"
    t.index ["juego_id"], name: "index_generos_juegos_on_juego_id"
  end

  create_table "generos_peliculas", force: :cascade do |t|
    t.bigint "pelicula_id", null: false
    t.bigint "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "orden"
    t.index ["genero_id"], name: "index_generos_peliculas_on_genero_id"
    t.index ["pelicula_id"], name: "index_generos_peliculas_on_pelicula_id"
  end

  create_table "generos_serie_tvs", force: :cascade do |t|
    t.bigint "serie_tv_id", null: false
    t.bigint "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["genero_id"], name: "index_generos_serie_tvs_on_genero_id"
    t.index ["serie_tv_id"], name: "index_generos_serie_tvs_on_serie_tv_id"
  end

  create_table "global_categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_global_categories_on_name", unique: true
  end

  create_table "global_products", force: :cascade do |t|
    t.string "name", null: false
    t.integer "presentation", default: 0, null: false
    t.integer "cant_presentation", default: 1, null: false
    t.boolean "exento", default: false, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "source_business_id"
    t.bigint "source_producto_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_global_products_on_name"
    t.index ["source_business_id", "source_producto_id"], name: "index_global_products_on_source_business_and_producto", unique: true
    t.index ["source_business_id"], name: "index_global_products_on_source_business_id"
  end

  create_table "global_profit_margin_presets", force: :cascade do |t|
    t.decimal "percentage", precision: 7, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["percentage"], name: "index_global_profit_margin_presets_on_percentage", unique: true
  end

  create_table "global_supplier_products", force: :cascade do |t|
    t.bigint "global_supplier_id", null: false
    t.bigint "global_product_id", null: false
    t.decimal "costo_mayor", precision: 12, scale: 2
    t.decimal "cantidad", precision: 12, scale: 2
    t.decimal "costo_menor", precision: 12, scale: 2
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "exento", default: false, null: false
    t.index ["exento"], name: "index_global_supplier_products_on_exento"
    t.index ["global_product_id"], name: "index_global_supplier_products_on_global_product_id"
    t.index ["global_supplier_id", "global_product_id"], name: "index_global_supplier_products_unique_pair", unique: true
    t.index ["global_supplier_id"], name: "index_global_supplier_products_on_global_supplier_id"
  end

  create_table "global_suppliers", force: :cascade do |t|
    t.string "name", null: false
    t.string "rif"
    t.string "phone"
    t.string "mobile_payment_phone"
    t.string "email"
    t.text "address"
    t.string "bank_account_number"
    t.string "pricing_currency_priority", default: "usd", null: false
    t.boolean "default_exento", default: false, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "source_business_id"
    t.bigint "source_supplier_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_global_suppliers_on_name"
    t.index ["source_business_id", "source_supplier_id"], name: "index_global_suppliers_on_source_business_and_supplier", unique: true
    t.index ["source_business_id"], name: "index_global_suppliers_on_source_business_id"
  end

  create_table "hidden_debt_groups", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "group_key", null: false
    t.datetime "hidden_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "group_key"], name: "index_hidden_debt_groups_on_business_id_and_group_key", unique: true
    t.index ["business_id"], name: "index_hidden_debt_groups_on_business_id"
  end

  create_table "inventory_absorption_simulations", force: :cascade do |t|
    t.bigint "destination_business_id", null: false
    t.bigint "source_business_id", null: false
    t.bigint "user_id"
    t.string "mode", null: false
    t.datetime "simulated_at", null: false
    t.jsonb "summary", default: {}, null: false
    t.jsonb "preview", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_business_id", "created_at"], name: "idx_absorption_simulations_destination_created"
    t.index ["destination_business_id"], name: "idx_on_destination_business_id_4b273fc8b9"
    t.index ["mode"], name: "index_inventory_absorption_simulations_on_mode"
    t.index ["source_business_id", "created_at"], name: "idx_absorption_simulations_source_created"
    t.index ["source_business_id"], name: "index_inventory_absorption_simulations_on_source_business_id"
    t.index ["user_id"], name: "index_inventory_absorption_simulations_on_user_id"
  end

  create_table "juegos", force: :cascade do |t|
    t.string "poster"
    t.string "name"
    t.integer "year"
    t.string "desarrollador"
    t.string "plataforma"
    t.text "sinopsis"
    t.string "audio"
    t.string "calidad"
    t.string "formato_video"
    t.string "codigo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disponible", default: true
    t.string "link_trailer"
  end

  create_table "loss_recovery_entries", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "venta_id", null: false
    t.bigint "account_id"
    t.datetime "occurred_at", null: false
    t.string "base_currency", null: false
    t.decimal "tasa_dolar", precision: 14, scale: 4, default: "0.0", null: false
    t.decimal "real_total_base", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "charged_total_base", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "excess_base", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "real_total_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "charged_total_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "excess_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_loss_recovery_entries_on_account_id"
    t.index ["business_id", "occurred_at"], name: "index_loss_recovery_entries_on_business_id_and_occurred_at"
    t.index ["business_id"], name: "index_loss_recovery_entries_on_business_id"
    t.index ["venta_id"], name: "index_loss_recovery_entries_on_venta_id", unique: true
  end

  create_table "loss_recovery_settings", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.boolean "active", default: false, null: false
    t.decimal "surcharge_percent", precision: 8, scale: 4, default: "0.0", null: false
    t.decimal "min_invoice_total_usd", precision: 12, scale: 2, default: "5.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_loss_recovery_settings_on_business_id", unique: true
  end

  create_table "managers", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "pack_unwrap_items", force: :cascade do |t|
    t.bigint "pack_unwrap_id", null: false
    t.bigint "source_product_variation_id"
    t.bigint "destination_product_variation_id"
    t.bigint "source_stock_lot_id", null: false
    t.bigint "destination_stock_lot_id", null: false
    t.decimal "packs_opened", precision: 12, scale: 2, null: false
    t.decimal "units_created", precision: 12, scale: 2, null: false
    t.decimal "source_unit_cost_usd", precision: 12, scale: 2, null: false
    t.decimal "destination_unit_cost_usd", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_variation_name"
    t.string "destination_variation_name"
    t.index ["destination_product_variation_id"], name: "index_pack_unwrap_items_on_destination_product_variation_id"
    t.index ["destination_stock_lot_id"], name: "index_pack_unwrap_items_on_destination_stock_lot_id"
    t.index ["pack_unwrap_id"], name: "index_pack_unwrap_items_on_pack_unwrap_id"
    t.index ["source_product_variation_id"], name: "index_pack_unwrap_items_on_source_product_variation_id"
    t.index ["source_stock_lot_id"], name: "index_pack_unwrap_items_on_source_stock_lot_id"
  end

  create_table "pack_unwraps", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "pack_producto_id", null: false
    t.bigint "unit_producto_id", null: false
    t.bigint "user_id", null: false
    t.integer "cant_presentation", null: false
    t.decimal "total_packs_opened", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_units_created", precision: 12, scale: 2, default: "0.0", null: false
    t.date "performed_on", null: false
    t.datetime "performed_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "performed_on"], name: "index_pack_unwraps_on_business_id_and_performed_on"
    t.index ["business_id"], name: "index_pack_unwraps_on_business_id"
    t.index ["pack_producto_id"], name: "index_pack_unwraps_on_pack_producto_id"
    t.index ["performed_on"], name: "index_pack_unwraps_on_performed_on"
    t.index ["unit_producto_id"], name: "index_pack_unwraps_on_unit_producto_id"
    t.index ["user_id"], name: "index_pack_unwraps_on_user_id"
  end

  create_table "peliculas", force: :cascade do |t|
    t.string "poster"
    t.string "name"
    t.string "others_titles"
    t.integer "duration_hours"
    t.integer "duration_minutes"
    t.string "director"
    t.string "reparto"
    t.text "sinopsis"
    t.string "codigo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disponible", default: true
    t.string "link_trailer"
    t.bigint "user_id", null: false
    t.date "date_estreno"
    t.string "clasification"
    t.decimal "promedio_ranking", precision: 12, scale: 2
    t.string "backdrop_image"
    t.index ["user_id"], name: "index_peliculas_on_user_id"
  end

  create_table "plataforma_peliculas", force: :cascade do |t|
    t.string "name"
    t.integer "escala"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "product_usages", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "producto_id", null: false
    t.bigint "product_variation_id"
    t.bigint "user_id", null: false
    t.decimal "quantity", precision: 14, scale: 3, null: false
    t.date "used_on", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "stock_lot_breakdown", default: [], null: false
    t.string "variation_name"
    t.index ["business_id", "used_on"], name: "index_product_usages_on_business_id_and_used_on"
    t.index ["business_id"], name: "index_product_usages_on_business_id"
    t.index ["product_variation_id"], name: "index_product_usages_on_product_variation_id"
    t.index ["producto_id", "product_variation_id"], name: "index_product_usages_on_producto_id_and_product_variation_id"
    t.index ["producto_id"], name: "index_product_usages_on_producto_id"
    t.index ["user_id"], name: "index_product_usages_on_user_id"
  end

  create_table "product_variations", force: :cascade do |t|
    t.bigint "producto_id", null: false
    t.string "description", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "safety_stock", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["producto_id"], name: "index_product_variations_on_producto_id"
  end

  create_table "productos", force: :cascade do |t|
    t.text "descripcion"
    t.decimal "precio_venta_usd", precision: 14, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "porcentaje_ganancia", precision: 7, scale: 2
    t.bigint "business_id", null: false
    t.bigint "categoria_id", null: false
    t.bigint "profit_margin_preset_id"
    t.boolean "exento", default: false, null: false
    t.integer "presentation", default: 0, null: false
    t.integer "cant_presentation", default: 1, null: false
    t.boolean "allow_unpack", default: false, null: false
    t.bigint "source_business_id"
    t.bigint "source_product_id"
    t.integer "general_safety_stock", default: 0, null: false
    t.bigint "global_product_id"
    t.boolean "show_in_catalog", default: true, null: false
    t.index "lower(descripcion) gin_trgm_ops", name: "index_productos_on_lower_descripcion_trgm", using: :gin
    t.index ["allow_unpack"], name: "index_productos_on_allow_unpack"
    t.index ["business_id", "global_product_id"], name: "index_productos_on_business_and_global_product"
    t.index ["business_id", "source_business_id", "source_product_id"], name: "index_productos_on_business_and_source_product", unique: true
    t.index ["business_id"], name: "index_productos_on_business_id"
    t.index ["categoria_id"], name: "index_productos_on_categoria_id"
    t.index ["global_product_id"], name: "index_productos_on_global_product_id"
    t.index ["profit_margin_preset_id"], name: "index_productos_on_profit_margin_preset_id"
    t.index ["source_business_id"], name: "index_productos_on_source_business_id"
  end

  create_table "profit_margin_presets", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.decimal "percentage", precision: 7, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "percentage"], name: "index_profit_margin_presets_on_business_and_percentage", unique: true
    t.index ["business_id"], name: "index_profit_margin_presets_on_business_id"
  end

  create_table "rankings", force: :cascade do |t|
    t.bigint "pelicula_id", null: false
    t.bigint "plataforma_pelicula_id", null: false
    t.decimal "valor", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pelicula_id"], name: "index_rankings_on_pelicula_id"
    t.index ["plataforma_pelicula_id"], name: "index_rankings_on_plataforma_pelicula_id"
  end

  create_table "recovery_invoice_items", force: :cascade do |t|
    t.bigint "recovery_invoice_id", null: false
    t.bigint "producto_id", null: false
    t.bigint "product_variation_id"
    t.decimal "quantity", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "unit_price_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total_price_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "lot_breakdown", default: []
    t.string "variation_name"
    t.index ["lot_breakdown"], name: "index_recovery_invoice_items_on_lot_breakdown", using: :gin
    t.index ["product_variation_id"], name: "index_recovery_invoice_items_on_product_variation_id"
    t.index ["producto_id"], name: "index_recovery_invoice_items_on_producto_id"
    t.index ["recovery_invoice_id"], name: "index_recovery_invoice_items_on_recovery_invoice_id"
  end

  create_table "recovery_invoices", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "user_id"
    t.datetime "occurred_at", null: false
    t.decimal "total_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_recovery_invoices_on_business_id"
    t.index ["user_id"], name: "index_recovery_invoices_on_user_id"
  end

  create_table "saime_users", force: :cascade do |t|
    t.integer "identification"
    t.string "entry"
    t.string "temporary_status", default: "activo", null: false
    t.string "confirmed_status", default: "activo", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "appointment_registration", default: false, null: false
    t.index ["user_id"], name: "index_saime_users_on_user_id"
  end

  create_table "scraper_statuses", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "healthy", default: true, null: false
    t.text "last_error_message"
    t.datetime "last_error_at"
    t.datetime "last_success_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_scraper_statuses_on_key", unique: true
  end

  create_table "serie_tvs", force: :cascade do |t|
    t.string "poster"
    t.string "name"
    t.string "others_title"
    t.integer "year"
    t.integer "temporadas"
    t.integer "capitulos"
    t.string "director"
    t.string "reparto"
    t.text "sinopsis"
    t.string "audio"
    t.string "calidad"
    t.string "status"
    t.string "formato_video"
    t.string "codigo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disponible", default: true
    t.string "link_trailer"
  end

  create_table "service_expense_structures", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.string "description", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active_for_sales", default: false, null: false
    t.index ["service_id"], name: "idx_service_exp_structures_active_sale_unique", unique: true, where: "(active_for_sales = true)"
    t.index ["service_id"], name: "index_service_expense_structures_on_service_id"
  end

  create_table "service_manager_expenses", force: :cascade do |t|
    t.bigint "service_expense_structure_id", null: false
    t.bigint "manager_id", null: false
    t.decimal "amount_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "amount_bs", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "currency_reference", default: "Dolar BCV", null: false
    t.decimal "amount_reference", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["manager_id"], name: "index_service_manager_expenses_on_manager_id"
    t.index ["service_expense_structure_id"], name: "index_service_manager_expenses_on_service_expense_structure_id"
  end

  create_table "service_managers", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.bigint "manager_id", null: false
    t.decimal "cost", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "reference_cost"
    t.index ["manager_id"], name: "index_service_managers_on_manager_id"
    t.index ["service_id"], name: "index_service_managers_on_service_id"
  end

  create_table "service_nested_expenses", force: :cascade do |t|
    t.bigint "service_expense_structure_id", null: false
    t.bigint "nested_service_id", null: false
    t.decimal "quantity", precision: 12, scale: 2, default: "1.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "currency_reference", default: "Bs", null: false
    t.decimal "amount_reference", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["nested_service_id"], name: "index_service_nested_expenses_on_nested_service_id"
    t.index ["service_expense_structure_id"], name: "index_service_nested_expenses_on_service_expense_structure_id"
  end

  create_table "service_print_coverage_prices", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.decimal "coverage_percent", precision: 5, scale: 2, null: false
    t.decimal "price_bs", precision: 14, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "coverage_percent"], name: "idx_print_coverage_unique", unique: true
    t.index ["service_id"], name: "index_service_print_coverage_prices_on_service_id"
  end

  create_table "service_print_material_surcharges", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.bigint "producto_id", null: false
    t.decimal "surcharge_percent", precision: 7, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.boolean "include_product_price_in_sale", default: false, null: false
    t.decimal "required_quantity", precision: 12, scale: 2, default: "1.0", null: false
    t.index ["description"], name: "index_service_print_material_surcharges_on_description"
    t.index ["include_product_price_in_sale"], name: "idx_print_material_include_product_price"
    t.index ["producto_id"], name: "index_service_print_material_surcharges_on_producto_id"
    t.index ["service_id", "producto_id"], name: "idx_service_print_material_surcharges_service_producto"
    t.index ["service_id"], name: "index_service_print_material_surcharges_on_service_id"
  end

  create_table "service_print_volume_discounts", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.integer "min_quantity", null: false
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "min_quantity"], name: "idx_service_print_volume_discounts_on_service_min_qty"
    t.index ["service_id"], name: "index_service_print_volume_discounts_on_service_id"
  end

  create_table "service_product_expenses", force: :cascade do |t|
    t.bigint "service_expense_structure_id", null: false
    t.bigint "producto_id", null: false
    t.decimal "quantity", precision: 12, scale: 2, default: "1.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "product_variation_id"
    t.boolean "breakdown_in_invoice", default: false, null: false
    t.index ["breakdown_in_invoice"], name: "index_service_product_expenses_on_breakdown_in_invoice"
    t.index ["product_variation_id"], name: "index_service_product_expenses_on_product_variation_id"
    t.index ["producto_id"], name: "index_service_product_expenses_on_producto_id"
    t.index ["service_expense_structure_id"], name: "index_service_product_expenses_on_service_expense_structure_id"
  end

  create_table "service_variable_expenses", force: :cascade do |t|
    t.bigint "service_expense_structure_id", null: false
    t.string "description", null: false
    t.decimal "amount_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "amount_bs", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "currency_reference", default: "Dolar BCV", null: false
    t.decimal "amount_reference", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["service_expense_structure_id"], name: "idx_on_service_expense_structure_id_c21a6b36d4"
  end

  create_table "services", force: :cascade do |t|
    t.string "description"
    t.boolean "cost"
    t.decimal "value_units", precision: 12, scale: 2
    t.decimal "sale_price", precision: 12, scale: 2
    t.string "currency_base_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "system_service_id"
    t.string "physical_requirements"
    t.string "digital_requirements"
    t.string "required_data"
    t.text "personal_steps"
    t.text "note"
    t.string "delivery_content"
    t.string "delivery_time"
    t.boolean "available", default: true, null: false
    t.string "pricing_mode", default: "fixed", null: false
    t.boolean "nested_available", default: false, null: false
    t.bigint "business_id", null: false
    t.boolean "caution_service", default: false, null: false
    t.boolean "restricted_service", default: false, null: false
    t.boolean "auto_cost_stock_discount", default: false, null: false
    t.boolean "post_sale_cost_debit", default: false, null: false
    t.boolean "delivery_physical_enabled", default: false, null: false
    t.boolean "delivery_digital_enabled", default: false, null: false
    t.bigint "print_delivery_service_id"
    t.jsonb "print_delivery_pages", default: [], null: false
    t.string "print_sale_description"
    t.bigint "print_delivery_material_surcharge_id"
    t.jsonb "print_delivery_extra_products", default: [], null: false
    t.decimal "recarga_min_amount", precision: 12, scale: 2
    t.decimal "recarga_multiple_amount", precision: 12, scale: 2
    t.decimal "recarga_profit_percent", precision: 5, scale: 2
    t.boolean "warn_digital_only_delivery_in_sales", default: false, null: false
    t.boolean "use_custom_image_for_display", default: false, null: false
    t.index "lower((description)::text) gin_trgm_ops", name: "index_services_on_lower_description_trgm", using: :gin
    t.index ["auto_cost_stock_discount"], name: "index_services_on_auto_cost_stock_discount"
    t.index ["business_id"], name: "index_services_on_business_id"
    t.index ["caution_service"], name: "index_services_on_caution_service"
    t.index ["nested_available"], name: "index_services_on_nested_available"
    t.index ["post_sale_cost_debit"], name: "index_services_on_post_sale_cost_debit"
    t.index ["pricing_mode"], name: "index_services_on_pricing_mode"
    t.index ["print_delivery_material_surcharge_id"], name: "index_services_on_print_delivery_material_surcharge_id"
    t.index ["print_delivery_service_id"], name: "index_services_on_print_delivery_service_id"
    t.index ["print_sale_description"], name: "index_services_on_print_sale_description"
    t.index ["restricted_service"], name: "index_services_on_restricted_service"
    t.index ["system_service_id"], name: "index_services_on_system_service_id"
  end

  create_table "stock_lot_variations", force: :cascade do |t|
    t.bigint "stock_lot_id", null: false
    t.bigint "product_variation_id"
    t.string "variation_description", null: false
    t.decimal "quantity_in", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "quantity_remaining", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_variation_id"], name: "index_stock_lot_variations_on_product_variation_id"
    t.index ["stock_lot_id", "product_variation_id"], name: "index_stock_lot_variations_on_lot_and_variation"
    t.index ["stock_lot_id"], name: "index_stock_lot_variations_on_stock_lot_id"
  end

  create_table "stock_lots", force: :cascade do |t|
    t.bigint "producto_id", null: false
    t.bigint "factura_item_id"
    t.bigint "supplier_id"
    t.decimal "unit_cost_usd", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "quantity_in", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "quantity_remaining", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "purchased_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "supplier_name"
    t.string "description"
    t.index ["description"], name: "index_stock_lots_on_description"
    t.index ["factura_item_id"], name: "index_stock_lots_on_factura_item_id", unique: true
    t.index ["producto_id", "purchased_at"], name: "index_stock_lots_on_producto_id_and_purchased_at"
    t.index ["producto_id"], name: "index_stock_lots_on_producto_id"
    t.index ["supplier_id"], name: "index_stock_lots_on_supplier_id"
  end

  create_table "supplier_products", force: :cascade do |t|
    t.bigint "supplier_id", null: false
    t.bigint "producto_id", null: false
    t.decimal "costo_mayor", precision: 12, scale: 2
    t.decimal "cantidad", precision: 12, scale: 2
    t.decimal "costo_menor", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "global_supplier_product_id"
    t.index ["global_supplier_product_id"], name: "index_supplier_products_on_global_supplier_product_id"
    t.index ["producto_id"], name: "index_supplier_products_on_producto_id"
    t.index ["supplier_id", "global_supplier_product_id"], name: "index_supplier_products_on_supplier_and_global_pair"
    t.index ["supplier_id", "producto_id"], name: "index_supplier_products_on_supplier_id_and_producto_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "nombre", null: false
    t.string "rif"
    t.string "telefono"
    t.string "email"
    t.text "direccion"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "nro_cuenta"
    t.string "telefono_pago_movil"
    t.string "pricing_currency_priority", default: "usd", null: false
    t.boolean "default_exento", default: false, null: false
    t.bigint "business_id", null: false
    t.bigint "global_supplier_id"
    t.index ["business_id", "global_supplier_id"], name: "index_suppliers_on_business_and_global_supplier"
    t.index ["business_id"], name: "index_suppliers_on_business_id"
    t.index ["global_supplier_id"], name: "index_suppliers_on_global_supplier_id"
  end

  create_table "system_services", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "recarga_min_amount", precision: 12, scale: 2
    t.decimal "recarga_multiple_amount", precision: 12, scale: 2
    t.decimal "recarga_profit_percent", precision: 5, scale: 2
    t.index "lower((name)::text) gin_trgm_ops", name: "index_system_services_on_lower_name_trgm", using: :gin
  end

  create_table "tasa_cambios", force: :cascade do |t|
    t.decimal "valor", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.date "fecha_referencia", null: false
    t.string "symbol", null: false
    t.index ["description", "fecha_referencia"], name: "index_tasa_cambios_unique_desc_fecha_ref", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "username", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false
    t.boolean "personal", default: false
    t.boolean "personal_saime", default: false, null: false
    t.bigint "business_id"
    t.string "full_name"
    t.boolean "active", default: true, null: false
    t.string "sex", default: "male", null: false
    t.index ["business_id"], name: "index_users_on_business_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["sex"], name: "index_users_on_sex"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "venta_items", force: :cascade do |t|
    t.bigint "venta_id", null: false
    t.bigint "producto_id"
    t.bigint "product_variation_id"
    t.string "product_name"
    t.string "variation_name"
    t.decimal "quantity", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "unit_price_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "subtotal_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "unit_price_base_amount", precision: 14, scale: 2
    t.string "unit_price_base_currency"
    t.boolean "exento", default: false, null: false
    t.index ["product_variation_id"], name: "index_venta_items_on_product_variation_id"
    t.index ["producto_id"], name: "index_venta_items_on_producto_id"
    t.index ["unit_price_base_currency"], name: "index_venta_items_on_unit_price_base_currency"
    t.index ["venta_id"], name: "index_venta_items_on_venta_id"
  end

  create_table "venta_payments", force: :cascade do |t|
    t.bigint "venta_id", null: false
    t.string "payment_method", null: false
    t.decimal "amount_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "amount_bs", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.string "currency", default: "USD", null: false
    t.decimal "amount_original", precision: 14, scale: 2, default: "0.0", null: false
    t.string "reference"
    t.string "payment_kind", default: "in", null: false
    t.date "payment_date"
    t.boolean "pending_validation", default: false, null: false
    t.index ["account_id", "reference", "payment_date"], name: "index_venta_payments_on_account_reference_payment_date"
    t.index ["account_id"], name: "index_venta_payments_on_account_id"
    t.index ["currency"], name: "index_venta_payments_on_currency"
    t.index ["payment_kind"], name: "index_venta_payments_on_payment_kind"
    t.index ["payment_method"], name: "index_venta_payments_on_payment_method"
    t.index ["pending_validation"], name: "index_venta_payments_on_pending_validation"
    t.index ["venta_id"], name: "index_venta_payments_on_venta_id"
  end

  create_table "ventas", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "status", default: "draft", null: false
    t.decimal "total_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total_bs", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "tasa_dolar", precision: 12, scale: 2
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "vat_mode", default: "none", null: false
    t.decimal "vat_rate", precision: 5, scale: 2, default: "0.16", null: false
    t.decimal "subtotal_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "vat_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.bigint "cliente_id"
    t.string "base_currency", default: "USD", null: false
    t.bigint "cash_shift_id"
    t.bigint "user_id"
    t.bigint "cashier_user_id"
    t.bigint "draft_lock_user_id"
    t.string "draft_lock_token"
    t.datetime "draft_lock_expires_at"
    t.index ["base_currency"], name: "index_ventas_on_base_currency"
    t.index ["business_id"], name: "index_ventas_on_business_id"
    t.index ["cash_shift_id"], name: "index_ventas_on_cash_shift_id"
    t.index ["cashier_user_id"], name: "index_ventas_on_cashier_user_id"
    t.index ["cliente_id"], name: "index_ventas_on_cliente_id"
    t.index ["draft_lock_expires_at"], name: "index_ventas_on_draft_lock_expires_at"
    t.index ["draft_lock_token"], name: "index_ventas_on_draft_lock_token", unique: true
    t.index ["status"], name: "index_ventas_on_status"
    t.index ["user_id"], name: "index_ventas_on_user_id"
    t.index ["vat_mode"], name: "index_ventas_on_vat_mode"
  end

  create_table "video_details", force: :cascade do |t|
    t.string "calidad"
    t.string "audio"
    t.string "peso"
    t.string "formato"
    t.string "resolucion"
    t.string "subtitulos"
    t.bigint "pelicula_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pelicula_id"], name: "index_video_details_on_pelicula_id"
  end

  add_foreign_key "account_movements", "account_settlements"
  add_foreign_key "account_movements", "accounts"
  add_foreign_key "account_movements", "cambio_efectivos"
  add_foreign_key "account_settlements", "accounts"
  add_foreign_key "account_settlements", "accounts", column: "settlement_account_id"
  add_foreign_key "accounts", "accounts", column: "settlement_account_id"
  add_foreign_key "accounts", "businesses"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointments", "saime_users"
  add_foreign_key "business_user_assignments", "businesses"
  add_foreign_key "business_user_assignments", "users"
  add_foreign_key "cambio_efectivos", "businesses"
  add_foreign_key "cambio_efectivos", "cash_shifts"
  add_foreign_key "cambio_efectivos", "users"
  add_foreign_key "cash_shifts", "businesses"
  add_foreign_key "cash_shifts", "users", column: "active_cashier_id"
  add_foreign_key "cash_shifts", "users", column: "closed_by_id"
  add_foreign_key "cash_shifts", "users", column: "opened_by_id"
  add_foreign_key "categorias", "businesses"
  add_foreign_key "clientes", "businesses"
  add_foreign_key "clientes", "users"
  add_foreign_key "debt_payments", "accounts"
  add_foreign_key "debt_payments", "debts"
  add_foreign_key "debts", "accounts", column: "mirror_account_id"
  add_foreign_key "debts", "businesses"
  add_foreign_key "debts", "clientes"
  add_foreign_key "debts", "debts", column: "mirror_debt_id"
  add_foreign_key "debts", "services", on_delete: :nullify
  add_foreign_key "debts", "ventas", on_delete: :nullify
  add_foreign_key "discount_schedules", "businesses"
  add_foreign_key "expense_categories", "businesses"
  add_foreign_key "expense_payments", "accounts"
  add_foreign_key "expense_payments", "expenses"
  add_foreign_key "expenses", "businesses"
  add_foreign_key "expenses", "expense_categories"
  add_foreign_key "factura_items", "facturas"
  add_foreign_key "factura_items", "productos", on_delete: :nullify
  add_foreign_key "facturas", "businesses"
  add_foreign_key "facturas", "businesses", column: "source_business_id"
  add_foreign_key "facturas", "suppliers", on_delete: :nullify
  add_foreign_key "generos_animes", "animes"
  add_foreign_key "generos_animes", "generos"
  add_foreign_key "generos_juegos", "generos"
  add_foreign_key "generos_juegos", "juegos"
  add_foreign_key "generos_peliculas", "generos"
  add_foreign_key "generos_peliculas", "peliculas"
  add_foreign_key "generos_serie_tvs", "generos"
  add_foreign_key "generos_serie_tvs", "serie_tvs"
  add_foreign_key "global_products", "businesses", column: "source_business_id"
  add_foreign_key "global_supplier_products", "global_products"
  add_foreign_key "global_supplier_products", "global_suppliers"
  add_foreign_key "global_suppliers", "businesses", column: "source_business_id"
  add_foreign_key "hidden_debt_groups", "businesses"
  add_foreign_key "inventory_absorption_simulations", "businesses", column: "destination_business_id"
  add_foreign_key "inventory_absorption_simulations", "businesses", column: "source_business_id"
  add_foreign_key "inventory_absorption_simulations", "users"
  add_foreign_key "loss_recovery_entries", "accounts"
  add_foreign_key "loss_recovery_entries", "businesses"
  add_foreign_key "loss_recovery_entries", "ventas"
  add_foreign_key "loss_recovery_settings", "businesses"
  add_foreign_key "pack_unwrap_items", "pack_unwraps"
  add_foreign_key "pack_unwrap_items", "product_variations", column: "destination_product_variation_id", on_delete: :nullify
  add_foreign_key "pack_unwrap_items", "product_variations", column: "source_product_variation_id", on_delete: :nullify
  add_foreign_key "pack_unwrap_items", "stock_lots", column: "destination_stock_lot_id"
  add_foreign_key "pack_unwrap_items", "stock_lots", column: "source_stock_lot_id"
  add_foreign_key "pack_unwraps", "businesses"
  add_foreign_key "pack_unwraps", "productos", column: "pack_producto_id"
  add_foreign_key "pack_unwraps", "productos", column: "unit_producto_id"
  add_foreign_key "pack_unwraps", "users"
  add_foreign_key "peliculas", "users"
  add_foreign_key "product_usages", "businesses"
  add_foreign_key "product_usages", "product_variations", on_delete: :nullify
  add_foreign_key "product_usages", "productos"
  add_foreign_key "product_usages", "users"
  add_foreign_key "product_variations", "productos"
  add_foreign_key "productos", "businesses"
  add_foreign_key "productos", "businesses", column: "source_business_id"
  add_foreign_key "productos", "categorias"
  add_foreign_key "productos", "global_products"
  add_foreign_key "productos", "profit_margin_presets"
  add_foreign_key "profit_margin_presets", "businesses"
  add_foreign_key "rankings", "peliculas"
  add_foreign_key "rankings", "plataforma_peliculas"
  add_foreign_key "recovery_invoice_items", "product_variations", on_delete: :nullify
  add_foreign_key "recovery_invoice_items", "productos"
  add_foreign_key "recovery_invoice_items", "recovery_invoices"
  add_foreign_key "recovery_invoices", "businesses"
  add_foreign_key "recovery_invoices", "users"
  add_foreign_key "saime_users", "users"
  add_foreign_key "service_expense_structures", "services"
  add_foreign_key "service_manager_expenses", "managers"
  add_foreign_key "service_manager_expenses", "service_expense_structures"
  add_foreign_key "service_managers", "managers"
  add_foreign_key "service_managers", "services"
  add_foreign_key "service_nested_expenses", "service_expense_structures"
  add_foreign_key "service_nested_expenses", "services", column: "nested_service_id"
  add_foreign_key "service_print_coverage_prices", "services"
  add_foreign_key "service_print_material_surcharges", "productos"
  add_foreign_key "service_print_material_surcharges", "services"
  add_foreign_key "service_print_volume_discounts", "services"
  add_foreign_key "service_product_expenses", "product_variations", on_delete: :nullify
  add_foreign_key "service_product_expenses", "productos"
  add_foreign_key "service_product_expenses", "service_expense_structures"
  add_foreign_key "service_variable_expenses", "service_expense_structures"
  add_foreign_key "services", "businesses"
  add_foreign_key "services", "service_print_material_surcharges", column: "print_delivery_material_surcharge_id"
  add_foreign_key "services", "services", column: "print_delivery_service_id"
  add_foreign_key "services", "system_services"
  add_foreign_key "stock_lot_variations", "product_variations", on_delete: :nullify
  add_foreign_key "stock_lot_variations", "stock_lots"
  add_foreign_key "stock_lots", "factura_items"
  add_foreign_key "stock_lots", "productos"
  add_foreign_key "stock_lots", "suppliers", on_delete: :nullify
  add_foreign_key "supplier_products", "global_supplier_products"
  add_foreign_key "supplier_products", "productos"
  add_foreign_key "supplier_products", "suppliers"
  add_foreign_key "suppliers", "businesses"
  add_foreign_key "suppliers", "global_suppliers"
  add_foreign_key "users", "businesses"
  add_foreign_key "venta_items", "product_variations", on_delete: :nullify
  add_foreign_key "venta_items", "productos"
  add_foreign_key "venta_items", "ventas"
  add_foreign_key "venta_payments", "accounts"
  add_foreign_key "venta_payments", "ventas"
  add_foreign_key "ventas", "businesses"
  add_foreign_key "ventas", "cash_shifts"
  add_foreign_key "ventas", "clientes"
  add_foreign_key "ventas", "users"
  add_foreign_key "ventas", "users", column: "cashier_user_id"
  add_foreign_key "ventas", "users", column: "draft_lock_user_id"
  add_foreign_key "video_details", "peliculas"
end
