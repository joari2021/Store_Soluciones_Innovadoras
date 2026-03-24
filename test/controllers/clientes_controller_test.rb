require "test_helper"
require "securerandom"

class ClientesControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = ["users"]
  fixtures :users

  setup do
    @user = users(:jorge)
    @business = Business.create!(name: "Negocio Clientes #{SecureRandom.hex(4)}")

    login_and_select_business!
  end

  test "create returns json payload for modal client creation" do
    assert_difference("Cliente.count", 1) do
      post clientes_path,
           params: {
             cliente: {
               document_type: "V",
               document_number: SecureRandom.random_number(10 ** 8).to_s.rjust(8, "0"),
               name: "Cliente Modal Ventas",
               phone: "04141234567",
               address: "Direccion prueba",
             },
           },
           as: :json
    end

    assert_response :created

    payload = JSON.parse(response.body)
    assert payload["id"].present?
    assert_equal "Cliente Modal Ventas", payload["name"]
    assert payload["document"].present?
  end

  private

  def login_and_select_business!
    post sessions_path, params: { login: @user.email, password: "215150603" }
    post select_business_path(@business)
  end
end
