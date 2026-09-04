require "test_helper"

class PlywoGithubRepositoryCapabilityProviderTest < ActiveSupport::TestCase
  Execution = Data.define(:context)

  class ExecutionModel
    def initialize(execution)
      @execution = execution
    end

    def find_by(execution_id:)
      @execution if execution_id == "github-123"
    end
  end

  class Authentication
    attr_reader :calls

    def initialize
      @calls = []
    end

    def installation_token(**attributes)
      @calls << attributes
      Plywo::Github::AppAuthentication::Token.new(
        value: "scoped-clone-token",
        expires_at: Time.utc(2026, 9, 5, 0, 0, 0)
      )
    end
  end

  test "mints a repository-scoped contents-read installation token" do
    authentication = Authentication.new
    provider = Plywo::Github::RepositoryCapabilityProvider.new(
      execution_model: ExecutionModel.new(
        Execution.new(context: { "installation_id" => 159_078_958 })
      ),
      authentication:
    )

    capability = provider.call(request: executor_request)

    assert_equal "scoped-clone-token", capability.token
    assert_equal(
      {
        installation_id: 159_078_958,
        repositories: [ "plywo" ],
        permissions: { contents: "read" }
      },
      authentication.calls.fetch(0)
    )
  end

  test "does not mint a capability without durable GitHub installation context" do
    authentication = Authentication.new
    provider = Plywo::Github::RepositoryCapabilityProvider.new(
      execution_model: ExecutionModel.new(nil),
      authentication:
    )

    assert_nil provider.call(request: executor_request)
    assert_empty authentication.calls
  end

  private

  def executor_request
    Plywo::Executor::Request.new(
      schema_version: "1",
      execution_id: "github-123",
      scenario_id: "scenario",
      baseline_sha: "base",
      candidate_sha: "head",
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
end
