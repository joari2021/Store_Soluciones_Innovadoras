require "test_helper"

class AnimesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @anime = animes(:one)
  end

  test "should get index" do
    get animes_url
    assert_response :success
  end

  test "should get new" do
    get new_anime_url
    assert_response :success
  end

  test "should create anime" do
    assert_difference("Anime.count") do
      post animes_url, params: { anime: { audio: @anime.audio, calidad: @anime.calidad, capitulos: @anime.capitulos, codigo: @anime.codigo, formato_video: @anime.formato_video, name: @anime.name, poster: @anime.poster, sinopsis: @anime.sinopsis, temporadas: @anime.temporadas, year: @anime.year } }
    end

    assert_redirected_to anime_url(Anime.last)
  end

  test "should show anime" do
    get anime_url(@anime)
    assert_response :success
  end

  test "should get edit" do
    get edit_anime_url(@anime)
    assert_response :success
  end

  test "should update anime" do
    patch anime_url(@anime), params: { anime: { audio: @anime.audio, calidad: @anime.calidad, capitulos: @anime.capitulos, codigo: @anime.codigo, formato_video: @anime.formato_video, name: @anime.name, poster: @anime.poster, sinopsis: @anime.sinopsis, temporadas: @anime.temporadas, year: @anime.year } }
    assert_redirected_to anime_url(@anime)
  end

  test "should destroy anime" do
    assert_difference("Anime.count", -1) do
      delete anime_url(@anime)
    end

    assert_redirected_to animes_url
  end
end
