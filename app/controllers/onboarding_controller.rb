class OnboardingController < ApplicationController
  def show
    @onboarding = Onboarding.new
    @onboarding.tidy!
    @terminal = Onboarding::LOGINS.keys.find { |name| @onboarding.running?(name) }
    @token = Factory.verifier.generate(@onboarding.tmux_name(@terminal), expires_in: 12.hours) if @terminal
  end

  def create
    name = params[:name].to_s
    Onboarding.new.launch(name) if Onboarding::LOGINS.key?(name) # whitelist — never launch arbitrary input
    redirect_to onboarding_path
  end
end
