require "test_helper"
require "tmpdir"

class Plywo::Runtime::ReadinessTest < ActiveSupport::TestCase
  test "production control plane is ready with isolated remote executor configuration" do
    Dir.mktmpdir("plywo-readiness-") do |root|
      File.write(File.join(root, "github.pem"), "private-key-placeholder")
      result = readiness(
        root:,
        env: control_plane_env.merge("PLYWO_GITHUB_PRIVATE_KEY_PATH" => "github.pem")
      ).call

      assert result.ready?, result.errors.inspect
      assert_equal "control_plane", result.role
    end
  end

  test "production control plane requires remote executor and https endpoints" do
    Dir.mktmpdir("plywo-readiness-") do |root|
      File.write(File.join(root, "github.pem"), "private-key-placeholder")
      env = control_plane_env.merge(
        "PLYWO_GITHUB_PRIVATE_KEY_PATH" => "github.pem",
        "PLYWO_PUBLIC_URL" => "http://plywo.example.test",
        "PLYWO_EXECUTOR" => "local",
        "PLYWO_REMOTE_EXECUTOR_URL" => "http://executor.example.test"
      )

      result = readiness(root:, env:).call

      assert_not result.ready?
      assert_includes result.errors, "PLYWO_PUBLIC_URL must be an absolute HTTPS URL"
      assert_includes result.errors, "PLYWO_EXECUTOR must be remote for a production control plane"
      assert_includes result.errors, "PLYWO_REMOTE_EXECUTOR_URL must be an absolute HTTPS URL"
    end
  end

  test "production control plane requires a repository allowlist" do
    Dir.mktmpdir("plywo-readiness-") do |root|
      File.write(File.join(root, "github.pem"), "private-key-placeholder")
      env = control_plane_env.merge("PLYWO_GITHUB_PRIVATE_KEY_PATH" => "github.pem")
      env.delete("PLYWO_GITHUB_REPOSITORY_ALLOWLIST")

      result = readiness(root:, env:).call

      assert_not result.ready?
      assert_includes result.errors, "PLYWO_GITHUB_REPOSITORY_ALLOWLIST is required for a production control plane"
    end
  end

  test "production control plane rejects wildcard repository admission" do
    Dir.mktmpdir("plywo-readiness-") do |root|
      File.write(File.join(root, "github.pem"), "private-key-placeholder")
      env = control_plane_env.merge(
        "PLYWO_GITHUB_PRIVATE_KEY_PATH" => "github.pem",
        "PLYWO_GITHUB_REPOSITORY_ALLOWLIST" => "*"
      )

      result = readiness(root:, env:).call

      assert_not result.ready?
      assert_includes result.errors, "PLYWO_GITHUB_REPOSITORY_ALLOWLIST must not contain * in production"
    end
  end

  test "production executor service is ready with git clone and no GitHub App secrets" do
    result = readiness(
      env: {
        "PLYWO_RUNTIME_ROLE" => "executor_service",
        "PLYWO_EXECUTOR_SERVICE_TOKEN" => "service-secret",
        "PLYWO_EXECUTOR_SERVICE_ADAPTER" => "git_clone"
      }
    ).call

    assert result.ready?, result.errors.inspect
    assert_equal "executor_service", result.role
  end

  test "production executor service rejects GitHub App secrets and recursive remote config" do
    result = readiness(
      env: {
        "PLYWO_RUNTIME_ROLE" => "executor_service",
        "PLYWO_EXECUTOR_SERVICE_TOKEN" => "service-secret",
        "PLYWO_EXECUTOR_SERVICE_ADAPTER" => "local",
        "PLYWO_GITHUB_PRIVATE_KEY_PATH" => "github.pem",
        "PLYWO_GITHUB_WEBHOOK_SECRET" => "webhook-secret",
        "PLYWO_EXECUTOR" => "remote",
        "PLYWO_REMOTE_EXECUTOR_URL" => "https://itself.example.test/v1/executions",
        "PLYWO_REMOTE_EXECUTOR_TOKEN" => "recursive-secret"
      }
    ).call

    assert_not result.ready?
    assert_includes result.errors, "PLYWO_EXECUTOR_SERVICE_ADAPTER must be git_clone for production executor service"
    assert_includes result.errors, "PLYWO_GITHUB_PRIVATE_KEY_PATH must not be configured on the executor service"
    assert_includes result.errors, "PLYWO_GITHUB_WEBHOOK_SECRET must not be configured on the executor service"
    assert_includes result.errors, "PLYWO_EXECUTOR=remote must not be configured on the executor service"
    assert_includes result.errors, "PLYWO_REMOTE_EXECUTOR_TOKEN must not be configured on the executor service"
    assert_not result.errors.join(" ").include?("recursive-secret")
  end

  test "combined production role fails readiness" do
    result = readiness(env: { "PLYWO_RUNTIME_ROLE" => "combined" }).call

    assert_not result.ready?
    assert_includes result.errors, "PLYWO_RUNTIME_ROLE=combined is not allowed for production readiness"
  end

  test "database failure fails readiness without exposing database error message" do
    result = Plywo::Runtime::Readiness.new(
      env: { "PLYWO_RUNTIME_ROLE" => "executor_service" },
      rails_env: "test",
      root: Rails.root,
      database_check: -> { raise RuntimeError, "postgres://secret-host/private" }
    ).call

    assert_not result.ready?
    assert_equal [ "Database connectivity failed (RuntimeError)" ], result.errors
  end

  private

  def readiness(env:, root: Rails.root)
    Plywo::Runtime::Readiness.new(
      env:,
      rails_env: "production",
      root:,
      database_check: -> { 1 }
    )
  end

  def control_plane_env
    {
      "PLYWO_RUNTIME_ROLE" => "control_plane",
      "PLYWO_PUBLIC_URL" => "https://plywo.example.test",
      "PLYWO_GITHUB_APP_ID" => "12345",
      "PLYWO_GITHUB_WEBHOOK_SECRET" => "webhook-secret",
      "PLYWO_GITHUB_REPOSITORY_ALLOWLIST" => "customer/app",
      "PLYWO_EXECUTOR" => "remote",
      "PLYWO_REMOTE_EXECUTOR_URL" => "https://executor.example.test/v1/executions",
      "PLYWO_REMOTE_EXECUTOR_TOKEN" => "service-secret"
    }
  end
end
