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
      delivery_id = request.headers["X-GitHub-Delivery"].to_s
      return render(json: { ok: false, error: "missing_delivery_id" }, status: :bad_request) if delivery_id.empty?

      body = JSON.parse(payload)
      delivery, enqueue = persist_delivery(event:, delivery_id:, body:)
      settle_non_execution_delivery!(delivery, event:, action: body["action"])
      enqueue_delivery!(delivery:, enqueue:, event:, action: body["action"])

      Rails.logger.info(
        "Plywo GitHub webhook accepted event=#{event.inspect} delivery=#{delivery_id.inspect} " \
        "action=#{body["action"].inspect} installation_id=#{body.dig("installation", "id").inspect} " \
        "repository=#{body.dig("repository", "full_name").inspect} pr=#{body["number"].inspect} " \
        "delivery_status=#{delivery.status.inspect}"
      )

      render json: {
        ok: true,
        event:,
        delivery: delivery_id,
        action: body["action"],
        installation_id: body.dig("installation", "id"),
        delivery_status: delivery.status
      }, status: :accepted
    rescue JSON::ParserError
      render json: { ok: false, error: "invalid_json" }, status: :bad_request
    end

    protected

    def append_info_to_payload(payload)
      super
      payload[:params] = {
        event: request.headers["X-GitHub-Event"].to_s,
        delivery: request.headers["X-GitHub-Delivery"].to_s
      }
    end

    private

    def persist_delivery(event:, delivery_id:, body:)
      existing = GithubWebhookDelivery.find_by(delivery_id:)
      if existing
        if existing.status == "failed"
          existing.update!(status: "accepted", failure: nil, started_at: nil, finished_at: nil)
          return [ existing, true ]
        end

        return [ existing, false ]
      end

      delivery = GithubWebhookDelivery.create!(
        delivery_id:,
        event:,
        action: body["action"],
        installation_id: body.dig("installation", "id"),
        repository: body.dig("repository", "full_name"),
        pull_request_number: body["number"],
        base_sha: body.dig("pull_request", "base", "sha"),
        head_sha: body.dig("pull_request", "head", "sha") || body.dig("check_run", "head_sha"),
        external_id: body.dig("check_run", "external_id")
      )

      [ delivery, true ]
    rescue ActiveRecord::RecordNotUnique
      [ GithubWebhookDelivery.find_by!(delivery_id:), false ]
    end

    def enqueue_delivery!(delivery:, enqueue:, event:, action:)
      return unless enqueue

      if event == "pull_request"
        GithubPullRequestWebhookJob.perform_later(delivery.id)
      elsif event == "check_run" && action == "rerequested"
        GithubCheckRunRerequestJob.perform_later(delivery.id)
      end
    end

    def settle_non_execution_delivery!(delivery, event:, action:)
      return if event == "pull_request"
      return if event == "check_run" && action == "rerequested"
      return unless delivery.status == "accepted"

      delivery.ignore!("event_not_execution_trigger")
    end
  end
end
