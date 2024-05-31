require "application_system_test_case"

class AnimesTest < ApplicationSystemTestCase
  setup do
    @anime = animes(:one)
  end

  test "visiting the index" do
    visit animes_url
    assert_selector "h1", text: "Animes"
  end

  test "should create anime" do
    visit animes_url
    click_on "New anime"

    fill_in "Audio", with: @anime.audio
    fill_in "Calidad", with: @anime.calidad
    fill_in "Capitulos", with: @anime.capitulos
    fill_in "Codigo", with: @anime.codigo
    fill_in "Formato video", with: @anime.formato_video
    fill_in "Name", with: @anime.name
    fill_in "Poster", with: @anime.poster
    fill_in "Sinopsis", with: @anime.sinopsis
    fill_in "Temporadas", with: @anime.temporadas
    fill_in "Year", with: @anime.year
    click_on "Create Anime"

    assert_text "Anime was successfully created"
    click_on "Back"
  end

  test "should update Anime" do
    visit anime_url(@anime)
    click_on "Edit this anime", match: :first

    fill_in "Audio", with: @anime.audio
    fill_in "Calidad", with: @anime.calidad
    fill_in "Capitulos", with: @anime.capitulos
    fill_in "Codigo", with: @anime.codigo
    fill_in "Formato video", with: @anime.formato_video
    fill_in "Name", with: @anime.name
    fill_in "Poster", with: @anime.poster
    fill_in "Sinopsis", with: @anime.sinopsis
    fill_in "Temporadas", with: @anime.temporadas
    fill_in "Year", with: @anime.year
    click_on "Update Anime"

    assert_text "Anime was successfully updated"
    click_on "Back"
  end

  test "should destroy Anime" do
    visit anime_url(@anime)
    click_on "Destroy this anime", match: :first

    assert_text "Anime was successfully destroyed"
  end
end
