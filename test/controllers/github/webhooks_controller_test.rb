require "test_helper"

class GithubWebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  test "persists but ignores a non-execution webhook" do
    with_webhook_secret do
      payload = JSON.generate(
        "action" => "created",
        "installation" => { "id" => 123 }
      )

      post_signed_webhook(payload:, event: "installation", delivery: "delivery-installation-1")

      assert_response :accepted
      body = response.parsed_body
      assert_equal true, body.fetch("ok")
      assert_equal "installation", body.fetch("event")
      assert_equal 123, body.fetch("installation_id")
      assert_equal "ignored", body.fetch("delivery_status")

      delivery = GithubWebhookDelivery.find_by!(delivery_id: "delivery-installation-1")
      assert_equal "installation", delivery.event
      assert_equal 123, delivery.installation_id
      assert_equal "ignored", delivery.status
      assert_equal "event_not_execution_trigger", delivery.failure
    end
  end

  test "persists and enqueues a pull request delivery once" do
    with_webhook_secret do
      payload = JSON.generate(
        "action" => "synchronize",
        "number" => 19,
        "installation" => { "id" => 158_885_061 },
        "repository" => { "full_name" => "plywo/plywo" },
        "pull_request" => {
          "base" => { "sha" => "base-sha" },
          "head" => { "sha" => "head-sha" }
        }
      )

      assert_enqueued_with(job: GithubPullRequestWebhookJob) do
        post_signed_webhook(payload:, event: "pull_request", delivery: "delivery-pr-1")
      end

      assert_response :accepted
      delivery = GithubWebhookDelivery.find_by!(delivery_id: "delivery-pr-1")
      assert_equal "plywo/plywo", delivery.repository
      assert_equal 19, delivery.pull_request_number
      assert_equal "base-sha", delivery.base_sha
      assert_equal "head-sha", delivery.head_sha

      assert_no_enqueued_jobs do
        post_signed_webhook(payload:, event: "pull_request", delivery: "delivery-pr-1")
      end
    end
  end

  test "settles completed check runs as ignored" do
    with_webhook_secret do
      payload = JSON.generate(
        "action" => "completed",
        "installation" => { "id" => 158_885_061 },
        "repository" => { "full_name" => "plywo/plywo" }
      )

      post_signed_webhook(payload:, event: "check_run", delivery: "delivery-check-run-completed")

      assert_response :accepted
      delivery = GithubWebhookDelivery.find_by!(delivery_id: "delivery-check-run-completed")
      assert_equal "ignored", delivery.status
      assert_equal "event_not_execution_trigger", delivery.failure
    end
  end

  test "records rerequested check runs as not implemented instead of leaving them accepted" do
    with_webhook_secret do
      payload = JSON.generate(
        "action" => "rerequested",
        "installation" => { "id" => 158_885_061 },
        "repository" => { "full_name" => "plywo/plywo" }
      )

      post_signed_webhook(payload:, event: "check_run", delivery: "delivery-check-run-rerequested")

      assert_response :accepted
      delivery = GithubWebhookDelivery.find_by!(delivery_id: "delivery-check-run-rerequested")
      assert_equal "ignored", delivery.status
      assert_equal "rerun_not_implemented", delivery.failure
    end
  end

  test "rejects an unsigned webhook" do
    with_webhook_secret do
      post github_webhooks_url,
        params: "{}",
        headers: {
          "CONTENT_TYPE" => "application/json",
          "X-GitHub-Event" => "ping",
          "X-GitHub-Delivery" => "delivery-unsigned"
        }

      assert_response :unauthorized
    end
  end

  private

  def with_webhook_secret
    previous_secret = ENV["PLYWO_GITHUB_WEBHOOK_SECRET"]
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = "development-secret"
    yield
  ensure
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = previous_secret
  end

  def post_signed_webhook(payload:, event:, delivery:)
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("PLYWO_GITHUB_WEBHOOK_SECRET"), payload)}"

    post github_webhooks_url,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-Hub-Signature-256" => signature,
        "X-GitHub-Event" => event,
        "X-GitHub-Delivery" => delivery
      }
  end
end
