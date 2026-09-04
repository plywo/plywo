Rails.application.routes.draw do
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check

  get "/github/app/register" => "github/app_manifests#new", as: :github_app_register
  get "/github/app/manifest/callback" => "github/app_manifests#callback", as: :github_app_manifest_callback
  post "/github/webhooks" => "github/webhooks#create", as: :github_webhooks

  if Rails.env.development? || Rails.env.test?
    post "/__plywo/demo/behavior" => "demo/behavior#create"
    post "/__plywo/demo/process-proof" => "demo/process_proof#create"
  end
end
