require "application_system_test_case"

class PeliculasTest < ApplicationSystemTestCase
  setup do
    @pelicula = peliculas(:one)
  end

  test "visiting the index" do
    visit peliculas_url
    assert_selector "h1", text: "Peliculas"
  end

  test "should create pelicula" do
    visit peliculas_url
    click_on "New pelicula"

    fill_in "Audio", with: @pelicula.audio
    fill_in "Calidad", with: @pelicula.calidad
    fill_in "Codigo", with: @pelicula.codigo
    fill_in "Director", with: @pelicula.director
    fill_in "Duration hours", with: @pelicula.duration_hours
    fill_in "Duration minutes", with: @pelicula.duration_minutes
    fill_in "Formato video", with: @pelicula.formato_video
    fill_in "Name", with: @pelicula.name
    fill_in "Others titles", with: @pelicula.others_titles
    fill_in "Poster", with: @pelicula.poster
    fill_in "Reparto", with: @pelicula.reparto
    fill_in "Sinopsis", with: @pelicula.sinopsis
    fill_in "Year", with: @pelicula.year
    click_on "Create Pelicula"

    assert_text "Pelicula was successfully created"
    click_on "Back"
  end

  test "should update Pelicula" do
    visit pelicula_url(@pelicula)
    click_on "Edit this pelicula", match: :first

    fill_in "Audio", with: @pelicula.audio
    fill_in "Calidad", with: @pelicula.calidad
    fill_in "Codigo", with: @pelicula.codigo
    fill_in "Director", with: @pelicula.director
    fill_in "Duration hours", with: @pelicula.duration_hours
    fill_in "Duration minutes", with: @pelicula.duration_minutes
    fill_in "Formato video", with: @pelicula.formato_video
    fill_in "Name", with: @pelicula.name
    fill_in "Others titles", with: @pelicula.others_titles
    fill_in "Poster", with: @pelicula.poster
    fill_in "Reparto", with: @pelicula.reparto
    fill_in "Sinopsis", with: @pelicula.sinopsis
    fill_in "Year", with: @pelicula.year
    click_on "Update Pelicula"

    assert_text "Pelicula was successfully updated"
    click_on "Back"
  end

  test "should destroy Pelicula" do
    visit pelicula_url(@pelicula)
    click_on "Destroy this pelicula", match: :first

    assert_text "Pelicula was successfully destroyed"
  end
end
