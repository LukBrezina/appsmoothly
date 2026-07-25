require "test_helper"

class PushControllerTest < ActionDispatch::IntegrationTest
  test "hands out the VAPID public key" do
    Push.stub :public_key, "PUBKEY" do
      get push_key_path
    end
    assert_response :success
    assert_equal "PUBKEY", JSON.parse(response.body)["key"]
  end

  test "stores a posted subscription" do
    stored = nil
    Push.stub :subscribe, ->(sub) { stored = sub } do
      post push_subscribe_path, params: {
        subscription: { endpoint: "https://push/a", keys: { p256dh: "x", auth: "y" } }
      }
    end
    assert_response :created
    assert_equal "https://push/a", stored["endpoint"]
    assert_equal "x", stored.dig("keys", "p256dh")
  end
end
