module Github
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def create
      payload = request.raw_post
      signature = request.headers["X-Hub-Signature-256"]
      secret = ENV["PLYWO_GITHUB_WEBHOOK_SECRET"]

      unless Plywo::Github::WebhookVerifier.new.valid?(payload:, signature:, secret:)
        return head :unauthorized
      end

      event = request.headers["X-GitHub-Event"].to_s
      delivery = request.headers["X-GitHub-Delivery"].to_s
      body = JSON.parse(payload)

      Rails.logger.info(
        "Plywo GitHub webhook accepted event=#{event.inspect} delivery=#{delivery.inspect} " \
        "action=#{body["action"].inspect} installation_id=#{body.dig("installation", "id").inspect}"
      )

      render json: {
        ok: true,
        event:,
        delivery:,
        action: body["action"],
        installation_id: body.dig("installation", "id")
      }, status: :accepted
    rescue JSON::ParserError
      render json: { ok: false, error: "invalid_json" }, status: :bad_request
    end
  end
end
