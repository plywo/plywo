require "test_helper"

class PlywoExecutionTest < ActiveSupport::TestCase
  test "claims a queued execution once and increments attempts" do
    execution = create_execution

    assert execution.claim!
    assert_equal "running", execution.status
    assert_equal 1, execution.attempt_count
    assert execution.started_at
    refute execution.claim!
  end

  test "stores the behavioral outcome on completion" do
    execution = create_execution
    execution.claim!

    payload = {
      "result" => { "decision" => "no_regression", "merge_recommendation" => "allow" },
      "run_id" => execution.execution_id
    }
    execution.complete!(payload)

    assert_equal "completed", execution.status
    assert_equal "no_regression", execution.decision
    assert_equal "allow", execution.outcome
    assert_equal payload, execution.result
    assert execution.finished_at
  end

  test "classifies failures as rerunnable infrastructure failures" do
    execution = create_execution
    execution.claim!
    execution.fail!(RuntimeError.new("worker unavailable"))

    assert_equal "failed", execution.status
    assert_equal "infra_failure", execution.outcome
    assert execution.rerunnable?

    assert execution.requeue!
    assert_equal "queued", execution.status
    assert_nil execution.outcome
    assert_nil execution.failure
    assert_nil execution.started_at
    assert_nil execution.finished_at
    assert_equal 1, execution.attempt_count

    assert execution.claim!
    assert_equal 2, execution.attempt_count
  end

  test "does not rerun completed behavioral outcomes" do
    execution = create_execution
    execution.claim!
    execution.complete!("result" => { "decision" => "review", "merge_recommendation" => "review" })

    refute execution.rerunnable?
    refute execution.requeue!
    assert_equal "completed", execution.status
    assert_equal "review", execution.outcome
  end

  test "classifies stale executions separately from infrastructure failures" do
    execution = create_execution
    execution.claim!
    execution.ignore!("stale_head_before_publish")

    assert_equal "ignored", execution.status
    assert_equal "stale", execution.outcome
    refute execution.rerunnable?
  end

  private

  def create_execution
    PlywoExecution.create!(
      execution_id: "github-#{SecureRandom.hex(16)}",
      source: "github_pull_request",
      scenario_id: "dogfood.git.behavior",
      baseline_sha: "base-sha",
      candidate_sha: "head-sha",
      context: {}
    )
  end
end
