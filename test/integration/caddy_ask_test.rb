require "test_helper"

class CaddyAskTest < ActionDispatch::IntegrationTest
  test "allows certificates only for preview hosts under this box's domain" do
    ENV["APPSMOOTHLY_DOMAIN"] = "acme.appsmoothly.com"
    get "/caddy_ask", params: { domain: "p-4567.preview.acme.appsmoothly.com" }
    assert_response :success
    # terminal./auth. must stay OUT: a host covered by the on-demand policy
    # never gets a proactive certificate, so approving them here kills sign-in.
    get "/caddy_ask", params: { domain: "terminal.acme.appsmoothly.com" }
    assert_response :not_found
    get "/caddy_ask", params: { domain: "p-4567.acme.appsmoothly.com" }
    assert_response :not_found
    get "/caddy_ask", params: { domain: "evil.preview.acme.appsmoothly.com" }
    assert_response :not_found
    get "/caddy_ask", params: { domain: "p-4567.preview.other.example.com" }
    assert_response :not_found
  ensure
    ENV.delete("APPSMOOTHLY_DOMAIN")
  end

  test "the approved shape is exactly what the TRY IT link points at" do
    ENV["APPSMOOTHLY_DOMAIN"] = "acme.appsmoothly.com"
    host = URI.parse(Factory.preview_url("ignored")).host
    get "/caddy_ask", params: { domain: host }
    assert_response :success
  ensure
    ENV.delete("APPSMOOTHLY_DOMAIN")
  end

  test "refuses everything when no domain is configured" do
    get "/caddy_ask", params: { domain: "p-4567.preview.acme.appsmoothly.com" }
    assert_response :not_found
  end
end
