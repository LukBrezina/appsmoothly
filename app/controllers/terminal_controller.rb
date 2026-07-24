class TerminalController < ApplicationController
  # The whole product: one always-there claude in a browser terminal. Everything
  # else — sessions, worktrees, deploys, previews of anything — claude does
  # itself, in here or on a page it publishes to /ui.
  def show
    return redirect_to onboarding_path unless Onboarding.ready?
    # Nothing built yet and claude never started → let them pick a starter first.
    return redirect_to onboarding_path if Factory.fresh? && !Agent.alive?

    Agent.ensure!(prompt: Onboarding::DEFAULT_PROMPT)
    @token = Factory.verifier.generate(Agent::NAME, expires_in: 12.hours)
  end
end
