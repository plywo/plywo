require "test_helper"

class Plywo::Runtime::RoleTest < ActiveSupport::TestCase
  test "development defaults to combined role" do
    role = Plywo::Runtime::Role.from_env(env: {}, rails_env: "development")

    assert_equal "combined", role.name
    assert role.control_plane?
    assert role.executor_service?
  end

  test "production defaults to control plane" do
    role = Plywo::Runtime::Role.from_env(env: {}, rails_env: "production")

    assert_equal "control_plane", role.name
    assert role.control_plane?
    assert_not role.executor_service?
  end

  test "legacy executor service flag resolves executor role" do
    role = Plywo::Runtime::Role.from_env(env: { "PLYWO_EXECUTOR_SERVICE" => "1" }, rails_env: "production")

    assert_equal "executor_service", role.name
    assert role.executor_service?
    assert_not role.control_plane?
  end

  test "explicit role wins over compatibility flag" do
    role = Plywo::Runtime::Role.from_env(
      env: {
        "PLYWO_RUNTIME_ROLE" => "control_plane",
        "PLYWO_EXECUTOR_SERVICE" => "1"
      },
      rails_env: "production"
    )

    assert_equal "control_plane", role.name
  end

  test "unknown role fails closed" do
    error = assert_raises(Plywo::Runtime::Role::Error) do
      Plywo::Runtime::Role.from_env(env: { "PLYWO_RUNTIME_ROLE" => "mystery" }, rails_env: "production")
    end

    assert_includes error.message, "Unsupported PLYWO_RUNTIME_ROLE"
  end
end
