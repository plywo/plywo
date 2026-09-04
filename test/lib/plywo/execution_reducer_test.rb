require "test_helper"

class PlywoExecutionReducerTest < ActiveSupport::TestCase
  test "folds durable worker observations into one execution" do
    execution = {
      "id" => "candidate",
      "measurements" => {
        "duration_ms" => 25.0,
        "sql_queries" => 14,
        "background_jobs" => 1,
        "emails" => 1,
        "http_requests" => 1,
        "errors" => 0
      },
      "attributions" => {
        "http_requests" => [ source("app/controllers/demo/behavior_controller.rb", 30) ]
      },
      "durable_observations" => [
        observation("sql_queries", "app/jobs/demo_async_evidence_job.rb", 3),
        observation("emails", "app/jobs/demo_async_evidence_job.rb", 4),
        observation("http_requests", "app/jobs/demo_async_evidence_job.rb", 5)
      ]
    }

    reduced = Plywo::ExecutionReducer.call(execution:)

    assert_equal 15, reduced.dig("measurements", "sql_queries")
    assert_equal 1, reduced.dig("measurements", "background_jobs")
    assert_equal 2, reduced.dig("measurements", "emails")
    assert_equal 2, reduced.dig("measurements", "http_requests")
    assert_equal 0, reduced.dig("measurements", "errors")
    assert_equal 25.0, reduced.dig("measurements", "duration_ms")
    assert_equal 3, reduced.dig("evidence", "durable_observations")
    assert_equal(
      [
        source("app/controllers/demo/behavior_controller.rb", 30),
        source("app/jobs/demo_async_evidence_job.rb", 5)
      ],
      reduced.dig("attributions", "http_requests")
    )
  end

  test "counts durable runtime errors" do
    execution = {
      "measurements" => { "errors" => 0 },
      "durable_observations" => [ { "signal" => "errors", "payload" => { "error_class" => "RuntimeError" } } ]
    }

    reduced = Plywo::ExecutionReducer.call(execution:)

    assert_equal 1, reduced.dig("measurements", "errors")
  end

  private

  def observation(signal, path, line)
    source(path, line).merge(
      "signal" => signal,
      "producer_kind" => "active_job",
      "producer_name" => "DemoAsyncEvidenceJob",
      "producer_id" => "job-1"
    )
  end

  def source(path, line)
    {
      "path" => path,
      "start_line" => line,
      "end_line" => line,
      "confidence" => "runtime"
    }
  end
end
