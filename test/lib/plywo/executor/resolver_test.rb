require "test_helper"

class PlywoExecutorResolverTest < ActiveSupport::TestCase
  test "resolves the local adapter from the new executor setting" do
    adapter = Plywo::Executor::Resolver.from_env(
      root: Rails.root,
      env: { "PLYWO_EXECUTOR" => "local" },
      rails_env: ActiveSupport::EnvironmentInquirer.new("test")
    )

    assert_instance_of Plywo::Executor::LocalAdapter, adapter
  end

  test "resolves the remote HTTP adapter from explicit configuration" do
    adapter = Plywo::Executor::Resolver.from_env(
      root: Rails.root,
      env: {
        "PLYWO_EXECUTOR" => "remote",
        "PLYWO_REMOTE_EXECUTOR_URL" => "https://executor.example.test/v1/executions",
        "PLYWO_REMOTE_EXECUTOR_TOKEN" => "secret",
        "PLYWO_REMOTE_EXECUTOR_OPEN_TIMEOUT_SECONDS" => "4",
        "PLYWO_REMOTE_EXECUTOR_READ_TIMEOUT_SECONDS" => "90"
      },
      rails_env: ActiveSupport::EnvironmentInquirer.new("test")
    )

    assert_instance_of Plywo::Executor::HttpAdapter, adapter
  end

  test "requires the remote executor URL and token" do
    error = assert_raises(Plywo::Executor::Resolver::Error) do
      Plywo::Executor::Resolver.from_env(
        root: Rails.root,
        env: { "PLYWO_EXECUTOR" => "remote" },
        rails_env: ActiveSupport::EnvironmentInquirer.new("test")
      )
    end

    assert_equal "PLYWO_REMOTE_EXECUTOR_URL is required", error.message

    error = assert_raises(Plywo::Executor::Resolver::Error) do
      Plywo::Executor::Resolver.from_env(
        root: Rails.root,
        env: {
          "PLYWO_EXECUTOR" => "remote",
          "PLYWO_REMOTE_EXECUTOR_URL" => "https://executor.example.test/v1/executions"
        },
        rails_env: ActiveSupport::EnvironmentInquirer.new("test")
      )
    end

    assert_equal "PLYWO_REMOTE_EXECUTOR_TOKEN is required", error.message
  end

  test "keeps the GitHub execution mode as a compatibility fallback" do
    adapter = Plywo::Executor::Resolver.from_env(
      root: Rails.root,
      env: { "PLYWO_GITHUB_EXECUTION_MODE" => "local" },
      rails_env: ActiveSupport::EnvironmentInquirer.new("test")
    )

    assert_instance_of Plywo::Executor::LocalAdapter, adapter
  end

  test "fails closed when execution is disabled" do
    error = assert_raises(Plywo::Executor::Resolver::Error) do
      Plywo::Executor::Resolver.from_env(
        root: Rails.root,
        env: { "PLYWO_EXECUTOR" => "disabled" },
        rails_env: ActiveSupport::EnvironmentInquirer.new("test")
      )
    end

    assert_equal "Plywo executor is disabled", error.message
  end
end
