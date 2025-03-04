require "test_helper"

class SaimeUsersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get saime_users_index_url
    assert_response :success
  end

  test "should get show" do
    get saime_users_show_url
    assert_response :success
  end

  test "should get new" do
    get saime_users_new_url
    assert_response :success
  end

  test "should get create" do
    get saime_users_create_url
    assert_response :success
  end

  test "should get edit" do
    get saime_users_edit_url
    assert_response :success
  end

  test "should get update" do
    get saime_users_update_url
    assert_response :success
  end

  test "should get destroy" do
    get saime_users_destroy_url
    assert_response :success
  end
end
