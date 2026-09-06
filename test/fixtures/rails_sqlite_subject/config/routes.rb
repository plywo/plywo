Rails.application.routes.draw do
  post "/__plywo/demo/behavior" => "demo/behavior#create"
end
