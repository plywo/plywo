require "test_helper"

class GithubPullRequestExecutionJobTest < ActiveJob::TestCase
  class TestJob < GithubPullRequestExecutionJob
    attr_accessor :authentication_override, :client_override, :executor_override, :publisher_override

    private

    def app_authentication
      authentication_override
    end

    def pull_request_client(token:)
      raise "unexpected token" unless token == "installation-token"

      client_override
    end

    def executor
      executor_override
    end

    def execution_publisher(token:)
      raise "unexpected publish token" unless token == "installation-token"

      publisher_override
    end
  end

  test "runs, publishes, and completes a current execution through a portable request" do
    execution = create_execution
    client = sequence_client([ current_pull_request, current_pull_request ])
    executor = counting_executor(payload)
    publisher = counting_publisher(check: :created, comment: :created)

    perform_job(execution:, client:, executor:, publisher:)

    execution.reload
    request = executor.requests.first
    assert_equal "completed", execution.status
    assert_equal "allow", execution.decision
    assert_equal "allow", execution.outcome
    assert_equal 1, execution.attempt_count
    assert_equal payload, execution.result
    assert_equal 1, executor.calls
    assert_equal 1, executor.requests.length
    assert_equal execution.execution_id, request.execution_id
    assert_equal 1, request.attempt_number
    refute_includes request.context, "installation_id"
    assert_equal 1, publisher.calls
  end

  test "classifies an executor error as infra failure and publishes that outcome" do
    execution = create_execution
    client = sequence_client([ current_pull_request, current_pull_request ])
    executor = failing_executor(RuntimeError.new("worker unavailable"))
    publisher = counting_publisher(check: :created, comment: :created)

    assert_raises(RuntimeError) do
      perform_job(execution:, client:, executor:, publisher:)
    end

    execution.reload
    assert_equal "failed", execution.status
    assert_equal "infra_failure", execution.outcome
    assert_equal 1, execution.attempt_count
    assert execution.rerunnable?
    assert_equal 1, publisher.infra_calls
  end

  test "ignores a stale head before dispatching to an executor" do
    execution = create_execution
    stale = current_pull_request.deep_dup
    stale["head"]["sha"] = "newer-head"
    executor = counting_executor(payload)
    publisher = counting_publisher(check: :created, comment: :created)

    perform_job(execution:, client: sequence_client([ stale ]), executor:, publisher:)

    assert_equal "ignored", execution.reload.status
    assert_equal "stale", execution.outcome
    assert_equal "stale_head", execution.failure
    assert_equal 0, executor.calls
    assert_equal 0, publisher.calls
  end

  test "does not publish when the baseline moves while the executor is active" do
    execution = create_execution
    moved = current_pull_request.deep_dup
    moved["base"]["sha"] = "newer-base"
    executor = counting_executor(payload)
    publisher = counting_publisher(check: :created, comment: :created)

    perform_job(
      execution:,
      client: sequence_client([ current_pull_request, moved ]),
      executor:,
      publisher:
    )

    assert_equal "ignored", execution.reload.status
    assert_equal "stale", execution.outcome
    assert_equal "stale_baseline_before_publish", execution.failure
    assert_equal 1, executor.calls
    assert_equal 0, publisher.calls
  end

  private

  def perform_job(execution:, client:, executor:, publisher:)
    job = TestJob.new
    job.authentication_override = fake_authentication
    job.client_override = client
    job.executor_override = executor
    job.publisher_override = publisher
    job.perform(execution.id)
  end

  def create_execution
    PlywoExecution.create!(
      execution_id: "github-#{SecureRandom.hex(32)}",
      source: "github_pull_request",
      scenario_id: "dogfood.git.behavior",
      baseline_sha: "base-sha",
      candidate_sha: "head-sha",
      context: {
        "repository" => "plywo/plywo",
        "pull_request_number" => 31,
        "installation_id" => 123,
        "delivery_id" => "secret-control-plane-detail",
        "baseline_ref" => "main",
        "candidate_ref" => "feature",
        "candidate_repository" => "plywo/plywo"
      }
    )
  end

  def payload
    { "run_id" => "run", "result" => { "decision" => "allow" } }
  end

  def current_pull_request
    {
      "base" => { "ref" => "main", "sha" => "base-sha" },
      "head" => { "ref" => "feature", "sha" => "head-sha" }
    }
  end

  def fake_authentication
    token = Plywo::Github::AppAuthentication::Token.new(
      value: "installation-token",
      expires_at: Time.utc(2026, 9, 4, 19, 30, 0)
    )

    Object.new.tap do |authentication|
      authentication.define_singleton_method(:installation_token) do |installation_id:|
        raise "unexpected installation" unless installation_id == 123

        token
      end
    end
  end

  def sequence_client(responses)
    queue = responses.dup
    Object.new.tap do |client|
      client.define_singleton_method(:fetch) do |repository:, number:|
        raise "unexpected repository" unless repository == "plywo/plywo"
        raise "unexpected pull request" unless number == 31

        queue.shift || raise("unexpected extra fetch")
      end
    end
  end

  def counting_executor(result)
    Struct.new(:result, :calls, :requests) do
      def call(request:)
        self.calls += 1
        requests << request
        result
      end
    end.new(result, 0, [])
  end

  def failing_executor(error)
    Object.new.tap do |executor|
      executor.define_singleton_method(:call) do |request:|
        raise "missing request" unless request

        raise error
      end
    end
  end

  def counting_publisher(result)
    Struct.new(:result, :calls, :infra_calls) do
      def call(execution:, payload:)
        raise "missing execution" unless execution
        raise "missing payload" unless payload

        self.calls += 1
        result
      end

      def infra_failure(execution:, error:)
        raise "missing execution" unless execution
        raise "missing error" unless error

        self.infra_calls += 1
        result
      end
    end.new(result, 0, 0)
  end
end
