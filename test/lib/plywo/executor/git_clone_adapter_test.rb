require "test_helper"
require "base64"

class PlywoExecutorGitCloneAdapterTest < ActiveSupport::TestCase
  class CommandRunner
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(env:, command:, chdir:)
      @calls << { env:, command:, chdir: }
      ""
    end
  end

  class Runner
    attr_reader :requests

    def initialize(payload)
      @payload = payload
      @requests = []
    end

    def call(execution:)
      @requests << execution
      @payload
    end
  end

  test "clones through an ephemeral header capability without putting the token in git arguments" do
    command_runner = CommandRunner.new
    runner = Runner.new(result_payload)
    repository_roots = []
    adapter = Plywo::Executor::GitCloneAdapter.new(
      root: Rails.root,
      command_runner:,
      runner_factory: lambda do |repository_root:|
        repository_roots << repository_root
        runner
      end
    )
    capability = Plywo::Executor::RepositoryCapability.new(token: "clone-token")

    result = adapter.call(request: executor_request, repository_capability: capability)

    assert result.success?
    assert_equal result_payload, result.payload
    assert_equal [ executor_request ], runner.requests

    fetch_call = command_runner.calls.find { |call| call.fetch(:command).take(2) == %w[git fetch] }
    assert fetch_call
    refute command_runner.calls.any? { |call| call.fetch(:command).join(" ").include?("clone-token") }

    expected_basic = Base64.strict_encode64("x-access-token:clone-token")
    assert_equal "AUTHORIZATION: basic #{expected_basic}", fetch_call.fetch(:env).fetch("GIT_CONFIG_VALUE_0")
    assert_equal "0", fetch_call.fetch(:env).fetch("GIT_TERMINAL_PROMPT")
    assert_includes fetch_call.fetch(:command), "+refs/heads/main:refs/remotes/origin/plywo-base"
    assert_includes fetch_call.fetch(:command), "+refs/pull/40/head:refs/remotes/origin/plywo-candidate"
    refute_predicate repository_roots.fetch(0), :exist?
  end

  test "fails closed when the repository capability is missing" do
    result = Plywo::Executor::GitCloneAdapter.new(
      root: Rails.root,
      command_runner: CommandRunner.new
    ).call(request: executor_request)

    assert result.failure?
    assert_equal "Plywo::Executor::GitCloneAdapter::Error", result.error_class
    assert_equal "Repository capability is required for git clone execution", result.error_message
  end

  test "fails closed for a fork until multiple repository capabilities are modeled" do
    request = executor_request.with(
      context: executor_request.context.merge("candidate_repository" => "someone/fork")
    )
    result = Plywo::Executor::GitCloneAdapter.new(
      root: Rails.root,
      command_runner: CommandRunner.new
    ).call(
      request:,
      repository_capability: Plywo::Executor::RepositoryCapability.new(token: "clone-token")
    )

    assert result.failure?
    assert_equal "Git clone executor currently supports same-repository pull requests only", result.error_message
  end

  private

  def executor_request
    @executor_request ||= Plywo::Executor::Request.new(
      schema_version: "1",
      execution_id: "github-1234567890abcdef",
      scenario_id: "scenario",
      baseline_sha: "base-sha",
      candidate_sha: "head-sha",
      attempt_number: 1,
      context: {
        "repository" => "plywo/plywo",
        "pull_request_number" => 40,
        "baseline_ref" => "main",
        "candidate_ref" => "feature",
        "candidate_repository" => "plywo/plywo"
      }
    )
  end

  def result_payload
    { "run_id" => "run", "result" => { "decision" => "allow" } }
  end
end
