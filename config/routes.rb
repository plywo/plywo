Rails.application.routes.draw do
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check

  if Rails.env.development? || Rails.env.test?
    post "/__plywo/demo/behavior" => "demo/behavior#create"
    post "/__plywo/demo/process-proof" => "demo/process_proof#create"
  end
end
