require "test_helper"

class PlywoExecutorServiceTest < ActiveSupport::TestCase
  test "executes once and replays the durable result for an identical idempotency key" do
    adapter = counting_adapter(Plywo::Executor::Result.success(result_payload))
    service = service(adapter:)

    first = service.call(idempotency_key: "github-123:1", request_payload: request_payload)
    second = service.call(idempotency_key: "github-123:1", request_payload: request_payload)

    assert first.success?
    assert second.success?
    assert_equal result_payload, second.payload
    assert_equal 1, adapter.calls
    assert_equal "completed", PlywoExecutorRequest.find_by!(idempotency_key: "github-123:1").status
  end

  test "preserves a worker failure as a durable portable result" do
    failure = Plywo::Executor::Result.new(
      schema_version: "1",
      status: "failed",
      payload: nil,
      error_class: "RemoteWorker::CheckoutError",
      error_message: "repository unavailable"
    )
    service = service(adapter: counting_adapter(failure))

    result = service.call(idempotency_key: "github-123:1", request_payload: request_payload)

    assert result.failure?
    assert_equal "RemoteWorker::CheckoutError", result.error_class
    assert_equal failure.to_h, PlywoExecutorRequest.find_by!(idempotency_key: "github-123:1").result
  end

  test "converts an adapter exception into a durable failed result" do
    adapter = Object.new
    adapter.define_singleton_method(:call) do |request:|
      raise "missing request" unless request

      raise RuntimeError, "worker crashed"
    end

    result = service(adapter:).call(
      idempotency_key: "github-123:1",
      request_payload: request_payload
    )

    assert result.failure?
    assert_equal "RuntimeError", result.error_class
    assert_equal "worker crashed", result.error_message
    assert_equal result.to_h, PlywoExecutorRequest.find_by!(idempotency_key: "github-123:1").result
  end

  test "fails closed when the worker adapter returns an unversioned payload" do
    service = service(adapter: counting_adapter(result_payload))

    result = service.call(idempotency_key: "github-123:1", request_payload: request_payload)

    assert result.failure?
    assert_equal "TypeError", result.error_class
    assert_equal "Executor service adapter must return Plywo::Executor::Result", result.error_message
  end

  test "rejects a duplicate request while the first claim is still live" do
    PlywoExecutorRequest.acquire!(
      idempotency_key: "github-123:1",
      request_payload: request_payload,
      lease_seconds: 60
    )

    error = assert_raises(Plywo::Executor::Service::RequestInProgress) do
      service(adapter: counting_adapter(Plywo::Executor::Result.success(result_payload))).call(
        idempotency_key: "github-123:1",
        request_payload: request_payload
      )
    end

    assert_equal "Executor request is already processing", error.message
  end

  test "rejects idempotency key reuse for a different request" do
    adapter = counting_adapter(Plywo::Executor::Result.success(result_payload))
    service = service(adapter:)
    service.call(idempotency_key: "github-123:1", request_payload: request_payload)

    changed = request_payload.merge("candidate_sha" => "different-head")
    assert_raises(Plywo::Executor::Service::RequestConflict) do
      service.call(idempotency_key: "github-123:1", request_payload: changed)
    end
  end

  private

  def service(adapter:)
    Plywo::Executor::Service.new(adapter:, lease_seconds: 60)
  end

  def counting_adapter(result)
    Struct.new(:result, :calls) do
      def call(request:)
        raise "missing request" unless request

        self.calls += 1
        result
      end
    end.new(result, 0)
  end

  def request_payload
    {
      "schema_version" => "1",
      "execution_id" => "github-123",
      "scenario_id" => "scenario",
      "baseline_sha" => "base",
      "candidate_sha" => "head",
      "attempt_number" => 1,
      "context" => {
        "repository" => "plywo/plywo",
        "pull_request_number" => 40,
        "baseline_ref" => "main",
        "candidate_ref" => "feature",
        "candidate_repository" => "plywo/plywo"
      }
    }
  end

  def result_payload
    { "run_id" => "run", "result" => { "decision" => "allow" } }
  end
end
