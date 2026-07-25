class UpdatesController < ApplicationController
  # Polled by the terminal page: is the factory behind its upstream?
  def check
    render json: Updater.status
  end

  # Apply the update. bin/update pulls, migrates, rebuilds and restarts the
  # service, so this returns immediately — the restart drops the socket and the
  # page reconnects (and reloads) onto the new version. Same authority the
  # terminal already grants (a real shell behind the box's loopback + Caddy).
  def create
    return head :conflict unless Updater.available?
    Updater.run!
    head :accepted
  end
end
