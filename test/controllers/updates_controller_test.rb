require "test_helper"

class UpdatesControllerTest < ActionDispatch::IntegrationTest
  test "check reports update status as json" do
    Updater.stub :status, { current: "aaa", latest: "bbb", behind: 2, available: true } do
      get update_check_path
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["available"]
    assert_equal 2, body["behind"]
  end

  test "update runs bin/update when a new version is available" do
    ran = false
    Updater.stub :available?, true do
      Updater.stub :run!, -> { ran = true } do
        post update_path
      end
    end
    assert ran, "should kick off bin/update"
    assert_response :accepted
  end

  test "update is a no-op when already current" do
    Updater.stub :available?, false do
      Updater.stub :run!, -> { flunk "must not update when already current" } do
        post update_path
      end
    end
    assert_response :conflict
  end
end
