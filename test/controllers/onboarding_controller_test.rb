require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  test "shows the sign-in card" do
    get onboarding_path
    assert_response :success
    assert_match "Claude", response.body
  end

  test "a picked starter reaches claude as its first task" do
    task = nil
    Agent.stub :ensure!, ->(prompt: nil) { task = prompt } do
      post onboarding_path, params: { starter: "starter" }
    end
    assert_redirected_to root_path
    assert_match Onboarding::STARTER_REPO, task
  end
end
