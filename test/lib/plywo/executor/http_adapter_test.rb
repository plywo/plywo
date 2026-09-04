require "test_helper"

class PlywoExecutorHttpAdapterTest < ActiveSupport::TestCase
  test "posts a versioned request and returns the portable result" do
    transport = recording_transport(
      status: 200,
      body: JSON.generate(Plywo::Executor::Result.success(payload).to_h)
    )
    adapter = adapter(transport:)

    result = adapter.call(request: executor_request)

    call = transport.calls.one
    assert_equal "https", call.fetch(:uri).scheme
    assert_equal "executor.example.test", call.fetch(:uri).host
    assert_equal "/v1/executions", call.fetch(:uri).path
    assert_equal "Bearer remote-secret", call.fetch(:headers).fetch("Authorization")
    assert_equal "github-123:2", call.fetch(:headers).fetch("Idempotency-Key")
    assert_equal executor_request.to_h, JSON.parse(call.fetch(:body))
    assert_equal 3, call.fetch(:open_timeout)
    assert_equal 120, call.fetch(:read_timeout)
    assert result.success?
    assert_equal payload, result.payload
  end

  test "preserves a remote worker failure result" do
    remote_failure = Plywo::Executor::Result.new(
      schema_version: "1",
      status: "failed",
      payload: nil,
      error_class: "RemoteWorker::CheckoutError",
      error_message: "repository unavailable"
    )
    transport = recording_transport(status: 200, body: JSON.generate(remote_failure.to_h))

    result = adapter(transport:).call(request: executor_request)

    assert result.failure?
    assert_equal "RemoteWorker::CheckoutError", result.error_class
    assert_equal "repository unavailable", result.error_message
  end

  test "fails on a non-success HTTP response" do
    transport = recording_transport(status: 503, body: "unavailable")

    error = assert_raises(Plywo::Executor::HttpAdapter::Error) do
      adapter(transport:).call(request: executor_request)
    end

    assert_equal "Remote executor returned HTTP 503", error.message
  end

  test "fails on malformed result JSON" do
    transport = recording_transport(status: 200, body: "not-json")

    error = assert_raises(Plywo::Executor::HttpAdapter::Error) do
      adapter(transport:).call(request: executor_request)
    end

    assert_match(/Remote executor returned invalid JSON/, error.message)
  end

  test "fails when the result is not a JSON object" do
    transport = recording_transport(status: 200, body: JSON.generate([]))

    error = assert_raises(Plywo::Executor::HttpAdapter::Error) do
      adapter(transport:).call(request: executor_request)
    end

    assert_equal "Remote executor result must be a JSON object", error.message
  end

  test "rejects insecure or incomplete configuration" do
    assert_raises(Plywo::Executor::HttpAdapter::Error) do
      Plywo::Executor::HttpAdapter.new(url: "file:///tmp/executor", token: "secret")
    end

    assert_raises(Plywo::Executor::HttpAdapter::Error) do
      Plywo::Executor::HttpAdapter.new(url: "https://executor.example.test", token: "")
    end
  end

  private

  def adapter(transport:)
    Plywo::Executor::HttpAdapter.new(
      url: "https://executor.example.test/v1/executions",
      token: "remote-secret",
      open_timeout: 3,
      read_timeout: 120,
      transport:
    )
  end

  def executor_request
    Plywo::Executor::Request.new(
      schema_version: "1",
      execution_id: "github-123",
      scenario_id: "scenario",
      baseline_sha: "base",
      candidate_sha: "head",
      attempt_number: 2,
      context: {
        "repository" => "plywo/plywo",
        "pull_request_number" => 39,
        "baseline_ref" => "main",
        "candidate_ref" => "feature",
        "candidate_repository" => "plywo/plywo"
      }
    )
  end

  def payload
    { "run_id" => "run", "result" => { "decision" => "allow" } }
  end

  def recording_transport(status:, body:)
    Struct.new(:response, :calls) do
      def call(**arguments)
        calls << arguments
        response
      end
    end.new(
      Plywo::Executor::HttpAdapter::Response.new(status:, body:),
      []
    )
  end
end
