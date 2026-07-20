Rails.application.routes.draw do
  root "apps#index"
  resources :apps, only: %i[new create]
  get "start" => "onboarding#show", as: :onboarding
  post "start" => "onboarding#create"
  get "start/link" => "onboarding#link", as: :onboarding_link

  scope ":app", constraints: { app: /\w+(?:-\w+)*/ } do
    resources :sessions, only: %i[index show create destroy] do
      resources :mails, only: %i[index show] do
        post :forward, on: :member
      end
    end
    resource :production, only: %i[show update] do
      post :deploy
    end
    get "backups" => "backups#show", as: :backups
    patch "backups" => "backups#update"
    post "backups/restore" => "backups#restore", as: :backups_restore
    post "backups/pull/:id" => "backups#pull", as: :backups_pull
  end

  # Caddy on-demand TLS gate: certificates only for p-<port> preview hosts
  # under this box's domain. Rack lambda so it needs no auth/session.
  get "caddy_ask" => ->(env) {
    domain = ENV["RAF_DOMAIN"]
    asked = Rack::Request.new(env).params["domain"].to_s
    ok = domain && asked.match?(/\Ap-\d+\.#{Regexp.escape(domain)}\z/)
    [ok ? 200 : 404, { "content-type" => "text/plain" }, []]
  }

  get "up" => "rails/health#show", as: :rails_health_check
end
