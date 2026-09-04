require "test_helper"

class PlywoGithubCheckRendererTest < ActiveSupport::TestCase
  test "maps an allowed result to a successful GitHub check" do
    rendered = Plywo::Github::CheckRenderer.call(
      payload: pair_payload(sql_queries: 14),
      run_url: "https://github.com/plywo/plywo/actions/runs/1"
    )

    assert_equal "Plywo / Behavioral Diff", rendered.fetch("name")
    assert_equal "success", rendered.fetch("conclusion")
    assert_equal "No behavioral regression detected", rendered.fetch("title")
    assert_includes rendered.fetch("summary"), "**ALLOW**"
    assert_includes rendered.fetch("summary"), "[Open execution](https://github.com/plywo/plywo/actions/runs/1)"
    assert_empty rendered.fetch("annotations")
  end

  test "renders a source-localized annotation for a trusted finding" do
    payload = pair_payload(
      sql_queries: 18,
      attributions: {
        "sql_queries" => [
          {
            "path" => "app/controllers/demo/behavior_controller.rb",
            "start_line" => 20,
            "end_line" => 20,
            "confidence" => "explicit"
          }
        ]
      },
      changed_paths: [ "app/controllers/demo/behavior_controller.rb" ]
    )
    rendered = Plywo::Github::CheckRenderer.call(payload:)
    annotation = rendered.fetch("annotations").first

    assert_equal "failure", rendered.fetch("conclusion")
    assert_equal "app/controllers/demo/behavior_controller.rb", annotation.fetch("path")
    assert_equal 20, annotation.fetch("start_line")
    assert_equal "failure", annotation.fetch("annotation_level")
    assert_includes annotation.fetch("message"), "14 to 18"
  end

  private

  def pair_payload(sql_queries:, attributions: {}, changed_paths: [])
    Plywo::ExecutionPair.call(
      baseline: execution(sql_queries: 14),
      candidate: execution(sql_queries:).merge("attributions" => attributions),
      changed_paths:
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
