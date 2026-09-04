require "test_helper"

class ExecutorExecutionsControllerTest < ActionDispatch::IntegrationTest
  test "returns a durable completed executor result to an authenticated caller" do
    with_executor_service_env do
      result = Plywo::Executor::Result.success(result_payload)
      acquisition = PlywoExecutorRequest.acquire!(
        idempotency_key: "github-123:1",
        request_payload: request_payload,
        lease_seconds: 60
      )
      acquisition.record.complete_claim!(
        claim_token: acquisition.claim_token,
        result_payload: result.to_h
      )

      post_executor(request_payload, idempotency_key: "github-123:1")

      assert_response :ok
      assert_equal result.to_h, response.parsed_body
    end
  end

  test "requires the executor service bearer token" do
    with_executor_service_env do
      post executor_service_executions_url,
        params: JSON.generate(request_payload),
        headers: {
          "CONTENT_TYPE" => "application/json",
          "Authorization" => "Bearer wrong-token",
          "Idempotency-Key" => "github-123:1"
        }

      assert_response :unauthorized
      assert_equal "Unauthorized", response.parsed_body.fetch("error")
    end
  end

  test "requires an idempotency key" do
    with_executor_service_env do
      post executor_service_executions_url,
        params: JSON.generate(request_payload),
        headers: authenticated_headers

      assert_response :bad_request
      assert_equal "Idempotency-Key is required", response.parsed_body.fetch("error")
    end
  end

  test "rejects an invalid portable request" do
    with_executor_service_env do
      invalid = request_payload.except("candidate_sha")
      post_executor(invalid, idempotency_key: "github-123:1")

      assert_response :unprocessable_entity
      assert_match(/candidate_sha/, response.parsed_body.fetch("error"))
    end
  end

  test "returns conflict while an identical request is already processing" do
    with_executor_service_env do
      PlywoExecutorRequest.acquire!(
        idempotency_key: "github-123:1",
        request_payload: request_payload,
        lease_seconds: 60
      )

      post_executor(request_payload, idempotency_key: "github-123:1")

      assert_response :conflict
      assert_equal "5", response.headers.fetch("Retry-After")
      assert_equal "Executor request is already processing", response.parsed_body.fetch("error")
    end
  end

  private

  def with_executor_service_env
    previous_token = ENV["PLYWO_EXECUTOR_SERVICE_TOKEN"]
    previous_adapter = ENV["PLYWO_EXECUTOR_SERVICE_ADAPTER"]
    previous_lease = ENV["PLYWO_EXECUTOR_SERVICE_REQUEST_LEASE_SECONDS"]

    ENV["PLYWO_EXECUTOR_SERVICE_TOKEN"] = "executor-secret"
    ENV["PLYWO_EXECUTOR_SERVICE_ADAPTER"] = "local"
    ENV["PLYWO_EXECUTOR_SERVICE_REQUEST_LEASE_SECONDS"] = "60"
    yield
  ensure
    ENV["PLYWO_EXECUTOR_SERVICE_TOKEN"] = previous_token
    ENV["PLYWO_EXECUTOR_SERVICE_ADAPTER"] = previous_adapter
    ENV["PLYWO_EXECUTOR_SERVICE_REQUEST_LEASE_SECONDS"] = previous_lease
  end

  def post_executor(payload, idempotency_key:)
    post executor_service_executions_url,
      params: JSON.generate(payload),
      headers: authenticated_headers.merge("Idempotency-Key" => idempotency_key)
  end

  def authenticated_headers
    {
      "CONTENT_TYPE" => "application/json",
      "Authorization" => "Bearer executor-secret"
    }
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
