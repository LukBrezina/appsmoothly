Rails.application.routes.draw do
  root "apps#index"
  resources :apps, only: %i[new create]
  get "start" => "onboarding#show", as: :onboarding
  post "start" => "onboarding#create"

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

  get "up" => "rails/health#show", as: :rails_health_check
end
