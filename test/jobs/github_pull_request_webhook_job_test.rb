require "test_helper"

class GithubPullRequestWebhookJobTest < ActiveJob::TestCase
  class TestJob < GithubPullRequestWebhookJob
    attr_accessor :authentication_override, :client_override

    private

    def app_authentication
      authentication_override
    end

    def pull_request_client(token:)
      raise "unexpected token" unless token == "installation-token"

      client_override
    end
  end

  test "authenticates the installation and completes a current execution trigger" do
    delivery = create_delivery(action: "synchronize")
    perform_job(delivery:, head_sha: "head-sha")

    assert_equal "completed", delivery.reload.status
    assert_nil delivery.failure
  end

  test "authenticates but ignores a pull request edit" do
    delivery = create_delivery(action: "edited")
    perform_job(delivery:, head_sha: "head-sha")

    assert_equal "ignored", delivery.reload.status
    assert_equal "action_not_execution_trigger", delivery.failure
  end

  test "ignores a stale webhook head" do
    delivery = create_delivery(action: "synchronize")
    perform_job(delivery:, head_sha: "newer-head")

    assert_equal "ignored", delivery.reload.status
    assert_equal "stale_head", delivery.failure
  end

  private

  def perform_job(delivery:, head_sha:)
    job = TestJob.new
    job.authentication_override = fake_authentication
    job.client_override = fake_client(head_sha:)
    job.perform(delivery.id)
  end

  def create_delivery(action:)
    GithubWebhookDelivery.create!(
      delivery_id: "delivery-#{action}-#{SecureRandom.hex(4)}",
      event: "pull_request",
      action:,
      installation_id: 158_885_061,
      repository: "plywo/plywo",
      pull_request_number: 19,
      base_sha: "base-sha",
      head_sha: "head-sha"
    )
  end

  def fake_authentication
    token = Plywo::Github::AppAuthentication::Token.new(
      value: "installation-token",
      expires_at: Time.utc(2026, 9, 4, 18, 30, 0)
    )

    Object.new.tap do |authentication|
      authentication.define_singleton_method(:installation_token) do |installation_id:|
        raise "unexpected installation" unless installation_id == 158_885_061

        token
      end
    end
  end

  def fake_client(head_sha:)
    Object.new.tap do |client|
      client.define_singleton_method(:fetch) do |repository:, number:|
        raise "unexpected repository" unless repository == "plywo/plywo"
        raise "unexpected pull request" unless number == 19

        { "head" => { "sha" => head_sha } }
      end
    end
  end
end
