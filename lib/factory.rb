require "json"

# Box facts: where the app lives, what the browser can reach, and the couple of
# tmux/claude quirks that need papering over. No state, no database — tmux and
# the filesystem are the only truth this factory has.
module Factory
  # Bundler env leaks from the factory into the tmux server it spawns; strip it
  # so `bundle` / `rails new` inside the session use the app's own bundle.
  BUNDLER_ENV = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_VERSION RUBYOPT RUBYLIB GEM_HOME GEM_PATH].freeze

  # One session means one dev server, so the preview port is a constant and the
  # TRY IT link never has to be looked up.
  PORT = 3100

  module_function

  def app_name = ENV["APPSMOOTHLY_APP"].to_s[/\A\w+(?:-\w+)*\z/] || "app"
  def projects_dir = File.expand_path(ENV.fetch("APPSMOOTHLY_PROJECTS_DIR", "~/projects"))
  def app_dir = File.join(projects_dir, app_name)

  # Anything claude writes here is served at /ui — that's how it shows the user
  # a page it built (an inbox, a version list, a chart) instead of us shipping one.
  def publish_dir = File.expand_path(ENV.fetch("APPSMOOTHLY_PUBLISH_DIR", "~/public"))

  # Set on provisioned boxes ("acme.appsmoothly.com"): the factory runs behind
  # Caddy/Authelia, previews become p-<port>.<domain>, deploys target this box.
  def domain = ENV["APPSMOOTHLY_DOMAIN"].presence

  # Previews live under *.preview.<domain>, never *.<domain>: Caddy's on-demand
  # policy for the wildcard would otherwise swallow terminal./auth. and their
  # certificates would never issue (see the Caddyfile in appsmoothly-infra).
  def preview_url(host) = domain ? "https://p-#{PORT}.preview.#{domain}" : "http://#{host.split(':').first}:#{PORT}"

  def fresh? = !Dir.exist?(app_dir) || Dir.empty?(app_dir)
  def ensure_dirs! = FileUtils.mkdir_p([app_dir, publish_dir])

  def verifier = Rails.application.message_verifier("rails_app_factory")

  def clean_tmux!
    system("tmux", "start-server")
    BUNDLER_ENV.each { |var| system("tmux", "set-environment", "-g", "-r", var) }
  end

  # Pre-accept claude's "do you trust this folder?" dialog. ponytail: best-effort,
  # last-write-wins on ~/.claude.json — worst case the dialog shows once.
  def trust!(path)
    file = File.expand_path("~/.claude.json")
    data = JSON.parse(File.read(file)) rescue {} # rubocop:disable Style/RescueModifier
    projects = (data["projects"] ||= {})
    return if projects.dig(path, "hasTrustDialogAccepted")
    (projects[path] ||= {})["hasTrustDialogAccepted"] = true
    File.write(file, JSON.generate(data))
  rescue StandardError
    nil
  end
end
