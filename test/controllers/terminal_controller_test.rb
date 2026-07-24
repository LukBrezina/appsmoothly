require "test_helper"

class TerminalControllerTest < ActionDispatch::IntegrationTest
  test "the terminal page is the whole app once there's something to work on" do
    Onboarding.stub :ready?, true do
      Factory.stub :fresh?, false do
        Agent.stub :ensure!, ->(prompt: nil) { } do
          get root_path
        end
      end
    end
    assert_response :success
    assert_match "TRY IT", response.body   # the running app
    assert_match "PAGES", response.body    # whatever claude published
    assert_match "id=\"mic\"", response.body
  end

  test "waits for sign-in before launching anything" do
    Onboarding.stub :ready?, false do
      Agent.stub :ensure!, ->(*) { flunk "must not launch claude before sign-in" } do
        get root_path
      end
    end
    assert_redirected_to onboarding_path
  end
end
