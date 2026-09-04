require "test_helper"

class PlywoExecutionTest < ActiveSupport::TestCase
  test "claims a queued execution once" do
    execution = create_execution

    assert execution.claim!
    assert_equal "running", execution.status
    assert execution.started_at
    refute execution.claim!
  end

  test "stores the behavioral decision on completion" do
    execution = create_execution
    execution.claim!

    payload = { "result" => { "decision" => "allow" }, "run_id" => execution.execution_id }
    execution.complete!(payload)

    assert_equal "completed", execution.status
    assert_equal "allow", execution.decision
    assert_equal payload, execution.result
    assert execution.finished_at
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
