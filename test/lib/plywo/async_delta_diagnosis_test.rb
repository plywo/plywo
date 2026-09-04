require "test_helper"

class PlywoAsyncDeltaDiagnosisTest < ActiveSupport::TestCase
  test "attributes queue-stage regression to enqueue-to-start delta" do
    result = Plywo::AsyncDeltaDiagnosis.call(
      queue_wait: signal(delta: 264.1, regression: true),
      worker_wall: signal(delta: 0.0)
    )

    assert_equal "enqueue_to_start_regression", result.fetch("classification")
    assert_equal 264.1, result.fetch("queue_wait_delta_ms")
    assert_equal 0.0, result.fetch("worker_wall_delta_ms")
    assert_equal 100.0, result.fetch("dominant_delta_share_percent")
  end

  test "attributes worker regression to worker runtime delta" do
    result = Plywo::AsyncDeltaDiagnosis.call(
      queue_wait: signal(delta: 5.0),
      worker_wall: signal(delta: 145.0, regression: true)
    )

    assert_equal "worker_runtime_regression", result.fetch("classification")
    assert_equal 3.3, result.fetch("enqueue_to_start_delta_share_percent")
    assert_equal 96.7, result.fetch("dominant_delta_share_percent")
  end

  test "keeps substantial positive growth in both stages as mixed" do
    result = Plywo::AsyncDeltaDiagnosis.call(
      queue_wait: signal(delta: 60.0, regression: true),
      worker_wall: signal(delta: 40.0, regression: true)
    )

    assert_equal "mixed_async_regression", result.fetch("classification")
    assert_equal 60.0, result.fetch("enqueue_to_start_delta_share_percent")
    assert_equal 60.0, result.fetch("dominant_delta_share_percent")
  end

  test "does not invent a causal regression when async signals are stable" do
    result = Plywo::AsyncDeltaDiagnosis.call(
      queue_wait: signal(delta: 8.0),
      worker_wall: signal(delta: -20.0)
    )

    assert_equal "no_async_regression", result.fetch("classification")
    assert_nil result.fetch("dominant_delta_share_percent")
  end

  test "returns unknown for capability mismatch" do
    result = Plywo::AsyncDeltaDiagnosis.call(
      queue_wait: signal(delta: nil, available: false),
      worker_wall: signal(delta: 10.0)
    )

    assert_equal "unknown", result.fetch("classification")
    assert_nil result.fetch("positive_async_delta_ms")
  end

  private

  def signal(delta:, regression: false, available: true)
    {
      "delta" => delta,
      "regression" => regression,
      "available" => available
    }
  end
end
