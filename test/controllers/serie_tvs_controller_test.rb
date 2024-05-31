require "test_helper"

class SerieTvsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @serie_tv = serie_tvs(:one)
  end

  test "should get index" do
    get serie_tvs_url
    assert_response :success
  end

  test "should get new" do
    get new_serie_tv_url
    assert_response :success
  end

  test "should create serie_tv" do
    assert_difference("SerieTv.count") do
      post serie_tvs_url, params: { serie_tv: { audio: @serie_tv.audio, calidad: @serie_tv.calidad, capitulos: @serie_tv.capitulos, codigo: @serie_tv.codigo, director: @serie_tv.director, formato_video: @serie_tv.formato_video, name: @serie_tv.name, others_title: @serie_tv.others_title, poster: @serie_tv.poster, reparto: @serie_tv.reparto, sinopsis: @serie_tv.sinopsis, status: @serie_tv.status, temporadas: @serie_tv.temporadas, year: @serie_tv.year } }
    end

    assert_redirected_to serie_tv_url(SerieTv.last)
  end

  test "should show serie_tv" do
    get serie_tv_url(@serie_tv)
    assert_response :success
  end

  test "should get edit" do
    get edit_serie_tv_url(@serie_tv)
    assert_response :success
  end

  test "should update serie_tv" do
    patch serie_tv_url(@serie_tv), params: { serie_tv: { audio: @serie_tv.audio, calidad: @serie_tv.calidad, capitulos: @serie_tv.capitulos, codigo: @serie_tv.codigo, director: @serie_tv.director, formato_video: @serie_tv.formato_video, name: @serie_tv.name, others_title: @serie_tv.others_title, poster: @serie_tv.poster, reparto: @serie_tv.reparto, sinopsis: @serie_tv.sinopsis, status: @serie_tv.status, temporadas: @serie_tv.temporadas, year: @serie_tv.year } }
    assert_redirected_to serie_tv_url(@serie_tv)
  end

  test "should destroy serie_tv" do
    assert_difference("SerieTv.count", -1) do
      delete serie_tv_url(@serie_tv)
    end

    assert_redirected_to serie_tvs_url
  end
end
