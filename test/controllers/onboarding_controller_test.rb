require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  test "shows the checklist" do
    get onboarding_path
    assert_response :success
    assert_match "Claude", response.body
    assert_match "GitHub", response.body
  end

  test "launches only whitelisted logins" do
    post onboarding_path, params: { name: "evil-name; rm -rf /" }
    assert_redirected_to onboarding_path
    assert_not system("tmux", "has-session", "-t", "=factory--evil-name; rm -rf /", err: File::NULL)
  end
end
