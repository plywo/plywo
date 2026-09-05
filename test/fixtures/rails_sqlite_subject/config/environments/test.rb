Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.active_job.queue_adapter = :test
end
