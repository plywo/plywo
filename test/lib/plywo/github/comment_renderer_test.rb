require "test_helper"

class PlywoGithubCommentRendererTest < ActiveSupport::TestCase
  test "renders a durable GitHub review comment with runtime evidence" do
    payload = Plywo::Demo::DogfoodRunner.call
    markdown = Plywo::Github::CommentRenderer.markdown(
      payload:,
      context: {
        repository: "plywo/plywo",
        pr_number: 1,
        baseline_label: "dogfood baseline",
        baseline_sha: "synthetic",
        candidate_label: "bootstrap/rails-first-slice",
        candidate_sha: "abcdef123456",
        bootstrap_baseline: true
      }
    )

    assert_includes markdown, Plywo::Github::CommentRenderer::MARKER
    assert_includes markdown, "Plywo · Behavioral Review"
    assert_includes markdown, "SQL queries"
    assert_includes markdown, "Merge recommendation: **BLOCK**"
    assert_includes markdown, "bootstrap dogfood run"
  end

  test "links real Git subjects and renders singular regression grammar" do
    payload = real_pair_payload
    markdown = Plywo::Github::CommentRenderer.markdown(
      payload:,
      context: {
        repository: "plywo/plywo",
        pr_number: 2,
        baseline_label: "main",
        baseline_sha: "0123456789abcdef",
        candidate_label: "feature",
        candidate_sha: "fedcba9876543210",
        execution_mode: "exact Git worktrees + isolated PostgreSQL databases"
      }
    )

    assert_includes markdown, "1 regression · 1 high"
    assert_includes markdown, "[`01234567`](https://github.com/plywo/plywo/commit/0123456789abcdef)"
    assert_includes markdown, "[`fedcba98`](https://github.com/plywo/plywo/commit/fedcba9876543210)"
    assert_includes markdown, "[Source diff](https://github.com/plywo/plywo/compare/0123456789abcdef...fedcba9876543210)"
    assert_includes markdown, "Evidence: exact Git worktrees + isolated PostgreSQL databases"
  end

  private

  def real_pair_payload
    baseline = execution(sql_queries: 14)
    candidate = execution(sql_queries: 19)
    Plywo::ExecutionPair.call(baseline:, candidate:)
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
