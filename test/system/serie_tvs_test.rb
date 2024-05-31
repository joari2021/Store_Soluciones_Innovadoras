require "application_system_test_case"

class SerieTvsTest < ApplicationSystemTestCase
  setup do
    @serie_tv = serie_tvs(:one)
  end

  test "visiting the index" do
    visit serie_tvs_url
    assert_selector "h1", text: "Serie tvs"
  end

  test "should create serie tv" do
    visit serie_tvs_url
    click_on "New serie tv"

    fill_in "Audio", with: @serie_tv.audio
    fill_in "Calidad", with: @serie_tv.calidad
    fill_in "Capitulos", with: @serie_tv.capitulos
    fill_in "Codigo", with: @serie_tv.codigo
    fill_in "Director", with: @serie_tv.director
    fill_in "Formato video", with: @serie_tv.formato_video
    fill_in "Name", with: @serie_tv.name
    fill_in "Others title", with: @serie_tv.others_title
    fill_in "Poster", with: @serie_tv.poster
    fill_in "Reparto", with: @serie_tv.reparto
    fill_in "Sinopsis", with: @serie_tv.sinopsis
    fill_in "Status", with: @serie_tv.status
    fill_in "Temporadas", with: @serie_tv.temporadas
    fill_in "Year", with: @serie_tv.year
    click_on "Create Serie tv"

    assert_text "Serie tv was successfully created"
    click_on "Back"
  end

  test "should update Serie tv" do
    visit serie_tv_url(@serie_tv)
    click_on "Edit this serie tv", match: :first

    fill_in "Audio", with: @serie_tv.audio
    fill_in "Calidad", with: @serie_tv.calidad
    fill_in "Capitulos", with: @serie_tv.capitulos
    fill_in "Codigo", with: @serie_tv.codigo
    fill_in "Director", with: @serie_tv.director
    fill_in "Formato video", with: @serie_tv.formato_video
    fill_in "Name", with: @serie_tv.name
    fill_in "Others title", with: @serie_tv.others_title
    fill_in "Poster", with: @serie_tv.poster
    fill_in "Reparto", with: @serie_tv.reparto
    fill_in "Sinopsis", with: @serie_tv.sinopsis
    fill_in "Status", with: @serie_tv.status
    fill_in "Temporadas", with: @serie_tv.temporadas
    fill_in "Year", with: @serie_tv.year
    click_on "Update Serie tv"

    assert_text "Serie tv was successfully updated"
    click_on "Back"
  end

  test "should destroy Serie tv" do
    visit serie_tv_url(@serie_tv)
    click_on "Destroy this serie tv", match: :first

    assert_text "Serie tv was successfully destroyed"
  end
end
