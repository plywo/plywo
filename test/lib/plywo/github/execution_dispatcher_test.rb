require "test_helper"

class PlywoGithubExecutionDispatcherTest < ActiveSupport::TestCase
  test "reuses one durable execution and safely re-enqueues while it is queued" do
    delivery = create_delivery
    pull_request = pull_request_payload
    dispatcher = Plywo::Github::ExecutionDispatcher.new(scenario_id: "scenario")

    first, first_enqueue = dispatcher.call(delivery:, pull_request:)
    second, second_enqueue = dispatcher.call(delivery:, pull_request:)

    assert first_enqueue
    assert second_enqueue
    assert_equal first.id, second.id
    assert_equal "queued", first.status
    assert_match(/\Agithub-[0-9a-f]{64}\z/, first.execution_id)
  end

  test "does not re-enqueue a completed execution for the same identity" do
    delivery = create_delivery
    dispatcher = Plywo::Github::ExecutionDispatcher.new(scenario_id: "scenario")
    execution, = dispatcher.call(delivery:, pull_request: pull_request_payload)
    execution.update!(status: "completed", decision: "allow", outcome: "allow", finished_at: Time.current)

    existing, enqueue = dispatcher.call(delivery:, pull_request: pull_request_payload)

    refute enqueue
    assert_equal execution.id, existing.id
    assert_equal "completed", existing.status
  end

  test "requeues an infra failure for the same identity" do
    delivery = create_delivery
    dispatcher = Plywo::Github::ExecutionDispatcher.new(scenario_id: "scenario")
    execution, = dispatcher.call(delivery:, pull_request: pull_request_payload)
    execution.claim!
    execution.fail!(RuntimeError.new("boom"))

    retried, enqueue = dispatcher.call(delivery:, pull_request: pull_request_payload)

    assert enqueue
    assert_equal execution.id, retried.id
    assert_equal "queued", retried.status
    assert_nil retried.outcome
    assert_nil retried.failure
    assert_nil retried.finished_at
  end

  test "does not requeue a failed execution without an infra failure outcome" do
    delivery = create_delivery
    dispatcher = Plywo::Github::ExecutionDispatcher.new(scenario_id: "scenario")
    execution, = dispatcher.call(delivery:, pull_request: pull_request_payload)
    execution.update!(status: "failed", failure: "manual stop", finished_at: Time.current)

    existing, enqueue = dispatcher.call(delivery:, pull_request: pull_request_payload)

    refute enqueue
    assert_equal execution.id, existing.id
    assert_equal "failed", existing.status
  end

  private

  def create_delivery
    GithubWebhookDelivery.create!(
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event: "pull_request",
      action: "synchronize",
      installation_id: 123,
      repository: "plywo/plywo",
      pull_request_number: 31,
      base_sha: "old-base",
      head_sha: "head-sha"
    )
  end

  def pull_request_payload
    {
      "base" => { "ref" => "main", "sha" => "base-sha" },
      "head" => {
        "ref" => "feature",
        "sha" => "head-sha",
        "repo" => { "full_name" => "plywo/plywo" }
      }
    }
  end
end
