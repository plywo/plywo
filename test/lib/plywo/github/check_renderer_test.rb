require "test_helper"

class PlywoGithubCheckRendererTest < ActiveSupport::TestCase
  test "maps an allowed result to a successful GitHub check" do
    rendered = Plywo::Github::CheckRenderer.call(payload: pair_payload(sql_queries: 14))

    assert_equal "Plywo / Behavioral Diff", rendered.fetch("name")
    assert_equal "success", rendered.fetch("conclusion")
    assert_equal "No behavioral regression detected", rendered.fetch("title")
    assert_includes rendered.fetch("summary"), "**ALLOW**"
  end

  test "maps a blocking regression to a failed GitHub check" do
    rendered = Plywo::Github::CheckRenderer.call(payload: pair_payload(sql_queries: 18))

    assert_equal "failure", rendered.fetch("conclusion")
    assert_equal "Behavioral regression detected", rendered.fetch("title")
    assert_includes rendered.fetch("summary"), "DATABASE_QUERY_REGRESSION"
    assert_includes rendered.fetch("summary"), "14 | 18"
  end

  private

  def pair_payload(sql_queries:)
    Plywo::ExecutionPair.call(
      baseline: execution(sql_queries: 14),
      candidate: execution(sql_queries:)
    )
  end

  def execution(sql_queries:)
    {
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
