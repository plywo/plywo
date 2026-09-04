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
