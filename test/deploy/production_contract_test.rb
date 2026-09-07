require "test_helper"
require "yaml"

class ProductionDeploymentContractTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("deploy/production")

  test "control plane keeps application ports private and GitHub key mounted read only" do
    compose = YAML.safe_load(ROOT.join("compose.control-plane.yml").read)
    services = compose.fetch("services")

    assert_equal ["3000"], services.dig("plywo", "expose")
    assert_nil services.dig("plywo", "ports")
    assert_includes services.dig("plywo", "volumes"), "./.secrets:/run/secrets:ro"
    assert_match(/PLYWO_CLOUDFLARED_IMAGE/, services.dig("tunnel", "image"))
  end

  test "executor keeps application and postgres ports private and infrastructure images pinned by contract" do
    compose = YAML.safe_load(ROOT.join("compose.executor.yml").read)
    services = compose.fetch("services")

    assert_equal ["3000"], services.dig("plywo", "expose")
    assert_nil services.dig("plywo", "ports")
    assert_nil services.dig("postgres", "ports")
    assert_match(/PLYWO_POSTGRES_IMAGE/, services.dig("postgres", "image"))
    assert_match(/PLYWO_CLOUDFLARED_IMAGE/, services.dig("tunnel", "image"))
  end

  test "executor environment example does not configure control-plane secrets or remote recursion" do
    env = ROOT.join("executor.env.example").read

    refute_match(/^PLYWO_GITHUB_PRIVATE_KEY_PATH=/, env)
    refute_match(/^PLYWO_GITHUB_WEBHOOK_SECRET=/, env)
    refute_match(/^PLYWO_REMOTE_EXECUTOR_URL=/, env)
    refute_match(/^PLYWO_REMOTE_EXECUTOR_TOKEN=/, env)
    refute_match(/^PLYWO_EXECUTOR=remote$/, env)

    assert_match(/^PLYWO_RUNTIME_ROLE=executor_service$/, env)
    assert_match(/^PLYWO_EXECUTOR_SERVICE_ADAPTER=git_clone$/, env)
  end

  test "control-plane environment example requires remote execution and production app identity" do
    env = ROOT.join("control-plane.env.example").read

    assert_match(/^PLYWO_RUNTIME_ROLE=control_plane$/, env)
    assert_match(/^PLYWO_GITHUB_APP_MANIFEST_ENV=production$/, env)
    assert_match(/^PLYWO_GITHUB_APP_SLUG=plywo$/, env)
    assert_match(/^PLYWO_EXECUTOR=remote$/, env)
    assert_match(%r{^PLYWO_REMOTE_EXECUTOR_URL=https://}, env)
  end
end
