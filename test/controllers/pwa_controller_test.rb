require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "serves an installable manifest" do
    get pwa_manifest_path
    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    assert_equal "standalone", JSON.parse(response.body)["display"]
  end

  test "serves the service worker at root scope" do
    get pwa_service_worker_path
    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_equal "/", response.headers["Service-Worker-Allowed"]
    assert_match "showNotification", response.body
  end
end
