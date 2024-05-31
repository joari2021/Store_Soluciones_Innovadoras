require "application_system_test_case"

class JuegosTest < ApplicationSystemTestCase
  setup do
    @juego = juegos(:one)
  end

  test "visiting the index" do
    visit juegos_url
    assert_selector "h1", text: "Juegos"
  end

  test "should create juego" do
    visit juegos_url
    click_on "New juego"

    fill_in "Audio", with: @juego.audio
    fill_in "Calidad", with: @juego.calidad
    fill_in "Codigo", with: @juego.codigo
    fill_in "Desarrollador", with: @juego.desarrollador
    fill_in "Formato video", with: @juego.formato_video
    fill_in "Name", with: @juego.name
    fill_in "Plataforma", with: @juego.plataforma
    fill_in "Poster", with: @juego.poster
    fill_in "Sinopsis", with: @juego.sinopsis
    fill_in "Year", with: @juego.year
    click_on "Create Juego"

    assert_text "Juego was successfully created"
    click_on "Back"
  end

  test "should update Juego" do
    visit juego_url(@juego)
    click_on "Edit this juego", match: :first

    fill_in "Audio", with: @juego.audio
    fill_in "Calidad", with: @juego.calidad
    fill_in "Codigo", with: @juego.codigo
    fill_in "Desarrollador", with: @juego.desarrollador
    fill_in "Formato video", with: @juego.formato_video
    fill_in "Name", with: @juego.name
    fill_in "Plataforma", with: @juego.plataforma
    fill_in "Poster", with: @juego.poster
    fill_in "Sinopsis", with: @juego.sinopsis
    fill_in "Year", with: @juego.year
    click_on "Update Juego"

    assert_text "Juego was successfully updated"
    click_on "Back"
  end

  test "should destroy Juego" do
    visit juego_url(@juego)
    click_on "Destroy this juego", match: :first

    assert_text "Juego was successfully destroyed"
  end
end
