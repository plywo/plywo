require "test_helper"

class PlywoExecutionPairTest < ActiveSupport::TestCase
  test "composes two real executions into the GitHub-compatible payload" do
    baseline = execution(id: "main", sql_queries: 14)
    candidate = execution(id: "candidate", sql_queries: 19)

    payload = Plywo::ExecutionPair.call(baseline:, candidate:)

    assert_equal "run-1", payload.fetch("run_id")
    assert_equal "scenario-1", payload.fetch("scenario_id")
    assert_equal "main", payload.dig("executions", "baseline", "id")
    assert_equal "candidate", payload.dig("executions", "candidate", "id")
    assert_equal "DATABASE_QUERY_REGRESSION", payload.dig("result", "findings", 0, "reason_code")
    assert_equal "block", payload.dig("result", "merge_recommendation")
  end

  test "attaches an explicit source only when the path changed" do
    baseline = execution(id: "main", sql_queries: 14)
    candidate = execution(id: "candidate", sql_queries: 19).merge(
      "attributions" => {
        "sql_queries" => [
          {
            "path" => "app/controllers/demo/behavior_controller.rb",
            "start_line" => 20,
            "end_line" => 20,
            "confidence" => "explicit"
          }
        ]
      }
    )

    trusted = Plywo::ExecutionPair.call(
      baseline:,
      candidate:,
      changed_paths: [ "app/controllers/demo/behavior_controller.rb" ]
    )
    untrusted = Plywo::ExecutionPair.call(
      baseline:,
      candidate:,
      changed_paths: [ "README.md" ]
    )

    assert_equal "app/controllers/demo/behavior_controller.rb", trusted.dig("result", "findings", 0, "source", "path")
    assert_nil untrusted.dig("result", "findings", 0, "source")
  end

  test "rejects executions from different scenarios" do
    baseline = execution(id: "main", sql_queries: 14)
    candidate = execution(id: "candidate", sql_queries: 14).merge("scenario_id" => "other")

    error = assert_raises(ArgumentError) do
      Plywo::ExecutionPair.call(baseline:, candidate:)
    end

    assert_equal "baseline and candidate must share run_id and scenario_id", error.message
  end

  private

  def execution(id:, sql_queries:)
    {
      "id" => id,
      "run_id" => "run-1",
      "scenario_id" => "scenario-1",
      "status" => "passed",
      "correlation_confirmed" => true,
      "measurements" => {
        "duration_ms" => 100,
        "sql_queries" => sql_queries,
        "background_jobs" => 1,
        "emails" => 1,
        "http_requests" => 1,
        "errors" => 0
      }
    }
  end
end
