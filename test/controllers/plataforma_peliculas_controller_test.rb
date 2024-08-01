require "test_helper"

class PlataformaPeliculasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @plataforma_pelicula = plataforma_peliculas(:one)
  end

  test "should get index" do
    get plataforma_peliculas_url
    assert_response :success
  end

  test "should get new" do
    get new_plataforma_pelicula_url
    assert_response :success
  end

  test "should create plataforma_pelicula" do
    assert_difference("PlataformaPelicula.count") do
      post plataforma_peliculas_url, params: { plataforma_pelicula: { escala: @plataforma_pelicula.escala, name: @plataforma_pelicula.name } }
    end

    assert_redirected_to plataforma_pelicula_url(PlataformaPelicula.last)
  end

  test "should show plataforma_pelicula" do
    get plataforma_pelicula_url(@plataforma_pelicula)
    assert_response :success
  end

  test "should get edit" do
    get edit_plataforma_pelicula_url(@plataforma_pelicula)
    assert_response :success
  end

  test "should update plataforma_pelicula" do
    patch plataforma_pelicula_url(@plataforma_pelicula), params: { plataforma_pelicula: { escala: @plataforma_pelicula.escala, name: @plataforma_pelicula.name } }
    assert_redirected_to plataforma_pelicula_url(@plataforma_pelicula)
  end

  test "should destroy plataforma_pelicula" do
    assert_difference("PlataformaPelicula.count", -1) do
      delete plataforma_pelicula_url(@plataforma_pelicula)
    end

    assert_redirected_to plataforma_peliculas_url
  end
end
