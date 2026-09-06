require "test_helper"

class ReadinessControllerTest < ActionDispatch::IntegrationTest
  test "returns ready status for the test combined role" do
    get "/ready"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "ready", payload.fetch("status")
    assert_equal "combined", payload.fetch("role")
    assert_equal [], payload.fetch("errors")
  end
end
