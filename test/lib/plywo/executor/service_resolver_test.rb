require "test_helper"

class PlywoExecutorServiceResolverTest < ActiveSupport::TestCase
  test "resolves only the local worker adapter by default" do
    adapter = Plywo::Executor::ServiceResolver.from_env(root: Rails.root, env: {})

    assert_instance_of Plywo::Executor::LocalAdapter, adapter
  end

  test "fails closed for an unsupported service adapter" do
    error = assert_raises(Plywo::Executor::ServiceResolver::Error) do
      Plywo::Executor::ServiceResolver.from_env(
        root: Rails.root,
        env: { "PLYWO_EXECUTOR_SERVICE_ADAPTER" => "remote" }
      )
    end

    assert_equal 'Unsupported PLYWO_EXECUTOR_SERVICE_ADAPTER="remote"', error.message
  end

  test "can disable the executor service adapter explicitly" do
    error = assert_raises(Plywo::Executor::ServiceResolver::Error) do
      Plywo::Executor::ServiceResolver.from_env(
        root: Rails.root,
        env: { "PLYWO_EXECUTOR_SERVICE_ADAPTER" => "disabled" }
      )
    end

    assert_equal "Plywo executor service adapter is disabled", error.message
  end
end
