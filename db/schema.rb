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

ActiveRecord::Schema[7.1].define(version: 2024_08_20_192217) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.float "promedio_ranking"
    t.string "backdrop_image"
    t.index ["user_id"], name: "index_peliculas_on_user_id"
  end

  create_table "plataforma_peliculas", force: :cascade do |t|
    t.string "name"
    t.integer "escala"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rankings", force: :cascade do |t|
    t.bigint "pelicula_id", null: false
    t.bigint "plataforma_pelicula_id", null: false
    t.float "valor", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pelicula_id"], name: "index_rankings_on_pelicula_id"
    t.index ["plataforma_pelicula_id"], name: "index_rankings_on_plataforma_pelicula_id"
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

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "username", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "generos_animes", "animes"
  add_foreign_key "generos_animes", "generos"
  add_foreign_key "generos_juegos", "generos"
  add_foreign_key "generos_juegos", "juegos"
  add_foreign_key "generos_peliculas", "generos"
  add_foreign_key "generos_peliculas", "peliculas"
  add_foreign_key "generos_serie_tvs", "generos"
  add_foreign_key "generos_serie_tvs", "serie_tvs"
  add_foreign_key "peliculas", "users"
  add_foreign_key "rankings", "peliculas"
  add_foreign_key "rankings", "plataforma_peliculas"
  add_foreign_key "video_details", "peliculas"
end
