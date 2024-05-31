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

ActiveRecord::Schema[7.1].define(version: 2024_05_31_030401) do
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
    t.string "genero"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "generos_animes", force: :cascade do |t|
    t.integer "anime_id", null: false
    t.integer "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["anime_id"], name: "index_generos_animes_on_anime_id"
    t.index ["genero_id"], name: "index_generos_animes_on_genero_id"
  end

  create_table "generos_juegos", force: :cascade do |t|
    t.integer "juego_id", null: false
    t.integer "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["genero_id"], name: "index_generos_juegos_on_genero_id"
    t.index ["juego_id"], name: "index_generos_juegos_on_juego_id"
  end

  create_table "generos_peliculas", force: :cascade do |t|
    t.integer "pelicula_id", null: false
    t.integer "genero_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["genero_id"], name: "index_generos_peliculas_on_genero_id"
    t.index ["pelicula_id"], name: "index_generos_peliculas_on_pelicula_id"
  end

  create_table "generos_serie_tvs", force: :cascade do |t|
    t.integer "serie_tv_id", null: false
    t.integer "genero_id", null: false
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
    t.integer "year"
    t.integer "duration_hours"
    t.integer "duration_minutes"
    t.string "director"
    t.string "reparto"
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

  add_foreign_key "generos_animes", "animes"
  add_foreign_key "generos_animes", "generos"
  add_foreign_key "generos_juegos", "generos"
  add_foreign_key "generos_juegos", "juegos"
  add_foreign_key "generos_peliculas", "generos"
  add_foreign_key "generos_peliculas", "peliculas"
  add_foreign_key "generos_serie_tvs", "generos"
  add_foreign_key "generos_serie_tvs", "serie_tvs"
end
