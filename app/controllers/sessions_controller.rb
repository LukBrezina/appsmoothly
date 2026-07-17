class SessionsController < AppScopedController
  RESERVED_SESSION_NAMES = Session::RESERVED

  def index
    @sessions = @app.sessions
    respond_to do |format|
      format.html
      format.json { render json: @sessions.map { |s| s.as_json(preview_host) } }
    end
  end

  def show
    @name = Factory.safe_name(params[:id]) or return redirect_to(sessions_path(@app))
    @sessions = @app.sessions
    @session = @sessions.find { |s| s.name == @name } ||
               Session.new(app: @app, name: @name).tap { |s| @sessions << s }
    # Asleep (the machine restarted since) → wake it: same worktree, Claude
    # continues its conversation. Only for persisted sessions — a typo URL
    # must not create workspaces.
    TmuxSession.launch(@app, @name, resume: true) if @session.persisted? && !@session.alive? && @app.ready?
    @token = Factory.verifier.generate(@session.tmux_name, expires_in: 12.hours)
  end

  def create
    prompt = params[:prompt].to_s.strip
    return redirect_to sessions_path(@app), alert: "Tell Claude what to work on in a few words" if prompt.blank?
    return redirect_to sessions_path(@app), alert: "#{@app.display_name} is still being built — give it a minute" unless @app.ready?

    name = Session.slug_for(@app, prompt)
    Session.create!(app: @app, name:, title: prompt)
    TmuxSession.launch(@app, name, prompt:)
    redirect_to session_path(@app, name)
  end

  def destroy
    name = Factory.safe_name(params[:id])
    if name
      TmuxSession.kill(@app, name) # kill tmux + teardown hook + remove worktree
      Session.where(app: @app, name:).destroy_all
    end
    redirect_to sessions_path(@app)
  end
end
