require "test_helper"

class CaddyAskTest < ActionDispatch::IntegrationTest
  test "allows certificates only for preview hosts under this box's domain" do
    ENV["RAF_DOMAIN"] = "acme.appsmoothly.com"
    get "/caddy_ask", params: { domain: "p-4567.acme.appsmoothly.com" }
    assert_response :success
    get "/caddy_ask", params: { domain: "evil.acme.appsmoothly.com" }
    assert_response :not_found
    get "/caddy_ask", params: { domain: "p-4567.other.example.com" }
    assert_response :not_found
  ensure
    ENV.delete("RAF_DOMAIN")
  end

  test "refuses everything when no domain is configured" do
    get "/caddy_ask", params: { domain: "p-4567.acme.appsmoothly.com" }
    assert_response :not_found
  end
end
