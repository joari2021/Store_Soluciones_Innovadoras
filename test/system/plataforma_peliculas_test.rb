require "application_system_test_case"

class PlataformaPeliculasTest < ApplicationSystemTestCase
  setup do
    @plataforma_pelicula = plataforma_peliculas(:one)
  end

  test "visiting the index" do
    visit plataforma_peliculas_url
    assert_selector "h1", text: "Plataforma peliculas"
  end

  test "should create plataforma pelicula" do
    visit plataforma_peliculas_url
    click_on "New plataforma pelicula"

    fill_in "Escala", with: @plataforma_pelicula.escala
    fill_in "Name", with: @plataforma_pelicula.name
    click_on "Create Plataforma pelicula"

    assert_text "Plataforma pelicula was successfully created"
    click_on "Back"
  end

  test "should update Plataforma pelicula" do
    visit plataforma_pelicula_url(@plataforma_pelicula)
    click_on "Edit this plataforma pelicula", match: :first

    fill_in "Escala", with: @plataforma_pelicula.escala
    fill_in "Name", with: @plataforma_pelicula.name
    click_on "Update Plataforma pelicula"

    assert_text "Plataforma pelicula was successfully updated"
    click_on "Back"
  end

  test "should destroy Plataforma pelicula" do
    visit plataforma_pelicula_url(@plataforma_pelicula)
    click_on "Destroy this plataforma pelicula", match: :first

    assert_text "Plataforma pelicula was successfully destroyed"
  end
end
