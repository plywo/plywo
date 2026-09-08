require "test_helper"

class PlywoSubjectRuntimeCapabilitiesTest < ActiveSupport::TestCase
  test "stores declared runtime and package-manager versions" do
    capabilities = Plywo::Subject::RuntimeCapabilities.new(
      runtimes: {
        ruby: "3.4.10",
        node: "24.0.0"
      },
      package_managers: {
        pnpm: "10.0.0"
      }
    )

    assert capabilities.runtime?("ruby")
    assert capabilities.runtime?(:node)
    assert capabilities.package_manager?("pnpm")
    assert_equal "3.4.10", capabilities.runtime_version("ruby")
    assert_equal "24.0.0", capabilities.runtime_version(:node)
    assert_equal "10.0.0", capabilities.package_manager_version(:pnpm)
    assert_equal(
      {
        "runtimes" => {
          "ruby" => "3.4.10",
          "node" => "24.0.0"
        },
        "package_managers" => {
          "pnpm" => "10.0.0"
        }
      },
      capabilities.to_h
    )
  end

  test "ruby_only declares the current Ruby and no JavaScript tooling" do
    capabilities = Plywo::Subject::RuntimeCapabilities.ruby_only(version: "3.4.10")

    assert_equal "3.4.10", capabilities.runtime_version("ruby")
    refute capabilities.runtime?("node")
    refute capabilities.runtime?("bun")
    refute capabilities.package_manager?("npm")
    refute capabilities.package_manager?("pnpm")
    refute capabilities.package_manager?("yarn")
    refute capabilities.package_manager?("bun")
  end

  test "loads executor capabilities from an explicit JSON environment declaration" do
    env = {
      Plywo::Subject::RuntimeCapabilities::ENV_KEY => JSON.generate(
        "runtimes" => {
          "ruby" => "3.4.10",
          "node" => "24.20.0"
        },
        "package_managers" => {
          "npm" => "11.19.0"
        }
      )
    }

    capabilities = Plywo::Subject::RuntimeCapabilities.from_env(env:, ruby_version: "3.4.10")

    assert_equal "3.4.10", capabilities.runtime_version("ruby")
    assert_equal "24.20.0", capabilities.runtime_version("node")
    assert_equal "11.19.0", capabilities.package_manager_version("npm")
  end

  test "falls back to Ruby-only capabilities when the executor declaration is absent" do
    capabilities = Plywo::Subject::RuntimeCapabilities.from_env(env: {}, ruby_version: "3.4.10")

    assert_equal "3.4.10", capabilities.runtime_version("ruby")
    refute capabilities.runtime?("node")
    refute capabilities.package_manager?("npm")
  end

  test "rejects invalid executor capability JSON instead of probing the host" do
    env = {
      Plywo::Subject::RuntimeCapabilities::ENV_KEY => "{"
    }

    error = assert_raises(Plywo::Subject::RuntimeCapabilities::Error) do
      Plywo::Subject::RuntimeCapabilities.from_env(env:, ruby_version: "3.4.10")
    end

    assert_match(/Invalid PLYWO_EXECUTOR_CAPABILITIES_JSON/, error.message)
  end

  test "rejects non-object executor capability JSON" do
    env = {
      Plywo::Subject::RuntimeCapabilities::ENV_KEY => "[]"
    }

    error = assert_raises(Plywo::Subject::RuntimeCapabilities::Error) do
      Plywo::Subject::RuntimeCapabilities.from_env(env:, ruby_version: "3.4.10")
    end

    assert_equal "PLYWO_EXECUTOR_CAPABILITIES_JSON must contain a JSON object", error.message
  end

  test "rejects capabilities without a version" do
    error = assert_raises(Plywo::Subject::RuntimeCapabilities::Error) do
      Plywo::Subject::RuntimeCapabilities.new(
        runtimes: { ruby: "" },
        package_managers: {}
      )
    end

    assert_equal 'Executor runtime capability "ruby" must declare a version', error.message
  end

  test "rejects non-mapping capability declarations" do
    error = assert_raises(Plywo::Subject::RuntimeCapabilities::Error) do
      Plywo::Subject::RuntimeCapabilities.new(
        runtimes: [ "ruby" ],
        package_managers: {}
      )
    end

    assert_equal "Executor runtime capabilities must be a mapping", error.message
  end
end
