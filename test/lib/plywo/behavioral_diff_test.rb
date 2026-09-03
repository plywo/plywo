require "test_helper"

class PlywoBehavioralDiffTest < ActiveSupport::TestCase
  test "detects regressions while functional outcome may still pass" do
    result = Plywo::BehavioralDiff.call(
      baseline: { duration_ms: 820, sql_queries: 14, background_jobs: 1, emails: 1, http_requests: 11, errors: 0 },
      candidate: { duration_ms: 1460, sql_queries: 47, background_jobs: 3, emails: 2, http_requests: 11, errors: 0 }
    )

    assert_equal "regression", result.fetch("decision")
    assert_equal "block", result.fetch("merge_recommendation")

    reason_codes = result.fetch("findings").map { |finding| finding.fetch("reason_code") }
    assert_includes reason_codes, "PERFORMANCE_REGRESSION"
    assert_includes reason_codes, "DATABASE_QUERY_REGRESSION"
    assert_includes reason_codes, "SIDE_EFFECT_CHANGED"
  end

  test "allows equivalent behavior" do
    measurements = { duration_ms: 820, sql_queries: 14, background_jobs: 1, emails: 1, http_requests: 11, errors: 0 }
    result = Plywo::BehavioralDiff.call(baseline: measurements, candidate: measurements)

    assert_equal "no_regression", result.fetch("decision")
    assert_equal "allow", result.fetch("merge_recommendation")
  end
end
