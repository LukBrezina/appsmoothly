class AppsController < ApplicationController
  def index
    return redirect_to onboarding_path unless Onboarding.new.done?

    app = App.order(:created_at).first
    redirect_to app ? sessions_path(app) : new_app_path
  end

  def new
    @app = App.new(agent: "claude")
  end

  def create
    @app = App.new(title: params.dig(:app, :title).to_s.strip, agent: params.dig(:app, :agent),
                   repo_url: params.dig(:app, :repo_url).to_s.strip.presence)
    if @app.save
      TmuxSession.launch_setup(@app)
      verb = @app.repo_url ? "Connecting" : "Building"
      redirect_to sessions_path(@app), notice: "#{verb} #{@app.display_name} — you can watch it happen live below."
    else
      flash.now[:alert] = @app.errors.full_messages.first
      render :new, status: :unprocessable_entity
    end
  end
end
