module Executor
  class ExecutionsController < ApplicationController
    skip_forgery_protection
    before_action :authenticate_executor_service!

    def create
      idempotency_key = request.headers["Idempotency-Key"].to_s
      return render_error("Idempotency-Key is required", status: :bad_request) if idempotency_key.empty?

      payload = JSON.parse(request.raw_post)
      return render_error("Executor request must be a JSON object", status: :unprocessable_entity) unless payload.is_a?(Hash)

      result = executor_service.call(idempotency_key:, request_payload: payload)
      render json: result.to_h, status: :ok
    rescue JSON::ParserError => error
      render_error("Invalid JSON: #{error.message}", status: :bad_request)
    rescue KeyError, ArgumentError => error
      render_error(error.message, status: :unprocessable_entity)
    rescue Plywo::Executor::Service::RequestConflict => error
      render_error(error.message, status: :conflict)
    rescue Plywo::Executor::Service::RequestInProgress => error
      response.set_header("Retry-After", "5")
      render_error(error.message, status: :conflict)
    rescue Plywo::Executor::Service::ClaimLost => error
      response.set_header("Retry-After", "5")
      render_error(error.message, status: :conflict)
    rescue Plywo::Executor::ServiceResolver::Error => error
      render_error(error.message, status: :service_unavailable)
    end

    private

    def authenticate_executor_service!
      token = ENV["PLYWO_EXECUTOR_SERVICE_TOKEN"].to_s
      if token.empty?
        render_error("Executor service token is not configured", status: :service_unavailable)
        return
      end

      expected = "Bearer #{token}"
      provided = request.authorization.to_s
      authenticated = provided.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render_error("Unauthorized", status: :unauthorized) unless authenticated
    end

    def executor_service
      Plywo::Executor::Service.new(adapter: executor_service_adapter)
    end

    def executor_service_adapter
      Plywo::Executor::ServiceResolver.from_env(root: Rails.root)
    end

    def render_error(message, status:)
      render json: { "error" => message }, status:
    end
  end
end
