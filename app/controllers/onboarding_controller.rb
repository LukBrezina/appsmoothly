class OnboardingController < ApplicationController
  def show
    Onboarding.tidy!
    @token = Factory.verifier.generate(Onboarding::TMUX, expires_in: 12.hours) if Onboarding.running?
  end

  # Opens a browser terminal running claude, which asks the user to sign in.
  def login
    Onboarding.launch!
    redirect_to onboarding_path
  end

  # Polled by the sign-in page — the link only appears mid-flow.
  def link
    render json: { url: Onboarding.login_url }
  end

  # Starter picked: hand it to claude as its first task and get out of the way.
  def create
    Agent.ensure!(prompt: Onboarding.first_prompt(params[:starter], params[:repo]))
    redirect_to root_path
  end
end
