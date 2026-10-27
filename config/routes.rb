Rails.application.routes.draw do
  root "landing#show"

  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resources :confirmations, param: :token, only: %i[new create show update]
  resources :unlocks, param: :token, only: %i[new create show update]
  resources :passwords, param: :token, only: %i[new create edit update]
  resources :invitations, param: :token, only: :show do
    resource :acceptance, only: :create, module: :invitations
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Jobs dashboard, for administrators only (the admin flag is set from the console).
  constraints(AdminConstraint) do
    mount MissionControl::Jobs::Engine, at: "/admin/jobs"
  end

  # Avatars and comment attachments, delivered only to users allowed to see them.
  get "files/:signed_id(/:variant)", to: "files#show", as: :file

  # The single-page application handles every path under /app.
  get "app(/*path)", to: "spa#show", as: :app, format: false

  namespace :api do
    resource :me, only: %i[show update], controller: "me" do
      resource :password, only: :update, module: :me
      resource :avatar, only: :update, module: :me
      resources :api_tokens, only: %i[index create destroy], module: :me
    end

    resources :teammates, only: :index
    resources :comments, only: %i[update destroy]
    get "announcements", to: "announcements#index"
    delete "announcements", to: "announcements#destroy"
    namespace :statistics do
      resource :overview, only: :show
      resources :deadlines, only: :index
    end
    resource :feedback, only: :create

    resources :projects, only: %i[index show create update destroy] do
      scope module: :projects do
        resource :membership, only: :destroy
        resources :invitations, only: %i[index create destroy]
        resources :members, only: %i[index destroy]
        resource :board, only: :show
        resources :statuses, only: %i[create update destroy]
        resources :tasks, only: %i[index show create update destroy] do
          scope module: :tasks do
            resource :placement, only: :update
            resources :subtasks, only: %i[index create]
            resource :completion, only: %i[update destroy]
            resource :label, only: %i[update destroy]
            resource :sprint, only: :update
            resources :comments, only: %i[index create]
          end
        end
        resources :labels, only: %i[index create]
        resources :milestones, only: %i[index show create destroy] do
          resource :recovery, only: :create, module: :milestones
        end
        resources :sprints, only: %i[index create] do
          scope module: :sprints do
            resource :activation, only: :create
            resource :archival, only: :create
            resources :tasks, only: :index
          end
        end
      end
    end

    # Documentation of the token API, for signed-in users (spec api-documentation).
    get "docs", to: "docs#show"
    get "openapi.yaml", to: "openapi#show", format: false, as: :openapi_document

    # Must stay last in the namespace: unknown API paths get the JSON 404 envelope.
    match "*path", to: "base#route_not_found", via: :all
  end
end
