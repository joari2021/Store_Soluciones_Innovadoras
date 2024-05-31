require "application_system_test_case"

class GenerosTest < ApplicationSystemTestCase
  setup do
    @genero = generos(:one)
  end

  test "visiting the index" do
    visit generos_url
    assert_selector "h1", text: "Generos"
  end

  test "should create genero" do
    visit generos_url
    click_on "New genero"

    fill_in "Genero", with: @genero.genero
    click_on "Create Genero"

    assert_text "Genero was successfully created"
    click_on "Back"
  end

  test "should update Genero" do
    visit genero_url(@genero)
    click_on "Edit this genero", match: :first

    fill_in "Genero", with: @genero.genero
    click_on "Update Genero"

    assert_text "Genero was successfully updated"
    click_on "Back"
  end

  test "should destroy Genero" do
    visit genero_url(@genero)
    click_on "Destroy this genero", match: :first

    assert_text "Genero was successfully destroyed"
  end
end
