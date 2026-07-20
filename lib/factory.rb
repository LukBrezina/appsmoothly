require "socket"
require "json"

module Factory
  # Bundler env leaks from the factory into the tmux server it spawns; strip it
  # so `rails new` / `bundle install` inside sessions use the target app's bundle.
  BUNDLER_ENV = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_VERSION RUBYOPT RUBYLIB GEM_HOME GEM_PATH].freeze

  module_function

  def projects_dir = File.expand_path(ENV.fetch("RAF_PROJECTS_DIR", "~/projects"))
  def worktrees_dir = File.join(projects_dir, ".worktrees")

  def safe_name(str)
    str.to_s[/\A\w+(?:-\w+)*\z/] # no "--" possible, so app--session splits unambiguously
  end

  def free_port
    server = TCPServer.new(0)
    server.addr[1].tap { server.close }
    # ponytail: tiny race between close and bin/dev binding; fine for a single-user tool
  end

  # Set on provisioned customer boxes (e.g. "acme.appsmoothly.com") — the factory
  # then runs behind Caddy/Authelia: previews become p-<port>.<domain> and
  # deploys target this same box (see Production).
  def domain = ENV["RAF_DOMAIN"].presence

  def preview_host
    @preview_host ||= JSON.parse(`tailscale status --json 2>/dev/null`).dig("Self", "DNSName").to_s.delete_suffix(".").presence
  rescue StandardError
    nil
  end

  def verifier = Rails.application.message_verifier("rails_app_factory")

  def clean_tmux!
    system("tmux", "start-server")
    BUNDLER_ENV.each { |var| system("tmux", "set-environment", "-g", "-r", var) }
  end
end
