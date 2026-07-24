Rails.application.routes.draw do
  # One screen: the terminal with the one claude session in it.
  root "terminal#show"

  # First run: sign claude in, then pick what to start from.
  get  "start"       => "onboarding#show", as: :onboarding
  post "start"       => "onboarding#create"
  post "start/login" => "onboarding#login", as: :onboarding_login
  get  "start/link"  => "onboarding#link", as: :onboarding_link

  # Claude's own UI. Anything it writes (or symlinks) into the publish dir is a
  # page the user can open — an inbox, a list of versions, a chart — so it can
  # build whatever screen the moment needs instead of us shipping one.
  mount Rack::Static.new(->(_env) { [404, { "content-type" => "text/plain" }, ["Nothing here yet"]] },
                         root: Factory.publish_dir, urls: [""], index: "index.html"),
        at: "/ui", as: :pages

  # Caddy on-demand TLS gate: certificates only for p-<port>.preview hosts under
  # this box's domain (the shape Factory.preview_url emits — anything wider and
  # terminal./auth. lose their proactive certs). Rack lambda: no auth/session.
  get "caddy_ask" => ->(env) {
    domain = ENV["APPSMOOTHLY_DOMAIN"]
    asked = Rack::Request.new(env).params["domain"].to_s
    ok = domain && asked.match?(/\Ap-\d+\.preview\.#{Regexp.escape(domain)}\z/)
    [ok ? 200 : 404, { "content-type" => "text/plain" }, []]
  }

  get "up" => "rails/health#show", as: :rails_health_check
end
