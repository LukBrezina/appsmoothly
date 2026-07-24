require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  # Shape of a real `tmux capture-pane -p` of claude's sign-in screen:
  # the URL is hard-wrapped across lines by the TUI.
  PANE = <<~TEXT
     Browser didn't open? Use the url below to sign in (c to copy)

    https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88
    ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.co
    m%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key&state=G9HQTBuBf2umch0cpf

     Paste code here if prompted >
  TEXT

  test "extract_url joins the wrapped sign-in link" do
    url = Onboarding.extract_url(PANE)
    assert_equal "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key&state=G9HQTBuBf2umch0cpf", url
  end

  test "extract_url grabs gh's device link without the trailing prose" do
    pane = "! First copy your one-time code: 1A2B-C3D4\nPress Enter to open https://github.com/login/device in your browser..."
    assert_equal "https://github.com/login/device", Onboarding.extract_url(pane)
  end

  test "extract_url is nil before the link appears" do
    assert_nil Onboarding.extract_url("Select login method:\n ❯ 1. Claude account\n")
  end

  test "the starter becomes a clone task" do
    assert_match Onboarding::STARTER_REPO, Onboarding.first_prompt("starter")
  end

  test "a typed repo has to look like a git address" do
    assert_match "https://github.com/me/app", Onboarding.first_prompt("repo", " https://github.com/me/app ")
    # anything else just opens claude rather than handing it junk to clone
    assert_equal Onboarding::DEFAULT_PROMPT, Onboarding.first_prompt("repo", "rm -rf / # not a url")
    assert_equal Onboarding::DEFAULT_PROMPT, Onboarding.first_prompt(nil)
  end
end
