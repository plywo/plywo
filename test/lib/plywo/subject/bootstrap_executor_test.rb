require "test_helper"

class PlywoSubjectBootstrapExecutorTest < ActiveSupport::TestCase
  class RecordingRubyBootstrap
    attr_reader :roots

    def initialize(environment: { "BUNDLE_FROZEN" => "true" })
      @environment = environment
      @roots = []
    end

    def call(root:)
      @roots << root
      @environment
    end
  end

  class RecordingJavascriptBootstrap
    attr_reader :calls

    def initialize(environment: {})
      @environment = environment
      @calls = []
    end

    def call(root:, step:)
      @calls << { root:, step: }
      @environment
    end
  end

  test "executes ruby.bundle through the typed Ruby handler when Ruby is declared" do
    ruby_bootstrap = RecordingRubyBootstrap.new
    executor = bootstrap_executor(ruby_bootstrap:)
    plan = setup_plan(
      {
        phase: "bootstrap",
        operation: "ruby.bundle",
        provenance: "detected",
        details: {
          manifest: "Gemfile",
          lockfile: "Gemfile.lock"
        }
      }
    )
    root = Pathname("/tmp/customer")

    environment = executor.call(root:, setup_plan: plan)

    assert_equal [ root ], ruby_bootstrap.roots
    assert_equal({ "BUNDLE_FROZEN" => "true" }, environment)
  end

  test "fails before Ruby bootstrap when the executor does not declare Ruby" do
    ruby_bootstrap = RecordingRubyBootstrap.new
    executor = bootstrap_executor(
      ruby_bootstrap:,
      runtime_capabilities: capabilities(runtimes: {})
    )
    plan = setup_plan(
      {
        phase: "bootstrap",
        operation: "ruby.bundle",
        provenance: "detected",
        details: {
          manifest: "Gemfile",
          lockfile: "Gemfile.lock"
        }
      }
    )

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_equal 'Bootstrap operation ruby.bundle requires executor runtime capability "ruby"', error.message
    assert_empty ruby_bootstrap.roots
  end

  test "rejects a ruby.bundle step that does not match the typed contract" do
    executor = bootstrap_executor
    plan = setup_plan(
      {
        phase: "bootstrap",
        operation: "ruby.bundle",
        provenance: "detected",
        details: {
          manifest: "Gemfile.custom",
          lockfile: "Gemfile.lock"
        }
      }
    )

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_match(/must use Gemfile and Gemfile.lock/, error.message)
  end

  test "JavaScript bootstrap requires a declared Node runtime" do
    javascript_bootstrap = RecordingJavascriptBootstrap.new
    executor = bootstrap_executor(javascript_bootstrap:)
    plan = javascript_plan(manager: "pnpm", lockfile: "pnpm-lock.yaml")

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_equal(
      'Bootstrap operation javascript.dependencies requires executor runtime capability "node"',
      error.message
    )
    assert_empty javascript_bootstrap.calls
  end

  test "JavaScript bootstrap requires the detected package manager capability" do
    javascript_bootstrap = RecordingJavascriptBootstrap.new
    executor = bootstrap_executor(
      javascript_bootstrap:,
      runtime_capabilities: capabilities(runtimes: { "ruby" => "3.4.10", "node" => "24.0.0" })
    )
    plan = javascript_plan(manager: "pnpm", lockfile: "pnpm-lock.yaml")

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_equal(
      'Bootstrap operation javascript.dependencies requires executor package-manager capability "pnpm"',
      error.message
    )
    assert_empty javascript_bootstrap.calls
  end

  test "declared JavaScript capabilities dispatch to the typed handler" do
    javascript_bootstrap = RecordingJavascriptBootstrap.new
    executor = bootstrap_executor(
      javascript_bootstrap:,
      runtime_capabilities: capabilities(
        runtimes: { "ruby" => "3.4.10", "node" => "24.0.0" },
        package_managers: { "pnpm" => "10.0.0" }
      )
    )
    plan = javascript_plan(manager: "pnpm", lockfile: "pnpm-lock.yaml")
    root = Pathname("/tmp/customer")

    environment = executor.call(root:, setup_plan: plan)

    assert_equal({}, environment)
    assert_equal 1, javascript_bootstrap.calls.length
    assert_equal root, javascript_bootstrap.calls.first.fetch(:root)
    assert_equal "javascript.dependencies", javascript_bootstrap.calls.first.fetch(:step).operation
  end

  test "Bun bootstrap requires a Bun runtime rather than Node" do
    javascript_bootstrap = RecordingJavascriptBootstrap.new
    executor = bootstrap_executor(
      javascript_bootstrap:,
      runtime_capabilities: capabilities(
        package_managers: { "bun" => "1.0.0" }
      )
    )
    plan = javascript_plan(manager: "bun", lockfile: "bun.lock")

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_equal(
      'Bootstrap operation javascript.dependencies requires executor runtime capability "bun"',
      error.message
    )
    assert_empty javascript_bootstrap.calls
  end

  test "never interprets an unknown operation as a command" do
    ruby_bootstrap = RecordingRubyBootstrap.new
    executor = bootstrap_executor(ruby_bootstrap:)
    plan = setup_plan(
      {
        phase: "bootstrap",
        operation: "rm -rf /",
        provenance: "explicit"
      }
    )

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_equal "Unsupported bootstrap operation \"rm -rf /\"", error.message
    assert_empty ruby_bootstrap.roots
  end

  test "requires a compiled setup plan" do
    executor = bootstrap_executor

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: nil)
    end

    assert_equal "Subject setup plan is required for bootstrap execution", error.message
  end

  private

  def bootstrap_executor(
    ruby_bootstrap: RecordingRubyBootstrap.new,
    javascript_bootstrap: RecordingJavascriptBootstrap.new,
    runtime_capabilities: capabilities
  )
    Plywo::Subject::BootstrapExecutor.new(
      ruby_bundle_bootstrap: ruby_bootstrap,
      javascript_dependencies_bootstrap: javascript_bootstrap,
      runtime_capabilities:
    )
  end

  def capabilities(runtimes: { "ruby" => "3.4.10" }, package_managers: {})
    Plywo::Subject::RuntimeCapabilities.new(runtimes:, package_managers:)
  end

  def javascript_plan(manager:, lockfile:)
    setup_plan(
      {
        phase: "bootstrap",
        operation: "javascript.dependencies",
        provenance: "detected",
        details: {
          manager:,
          manifest: "package.json",
          lockfile:,
          frozen_lockfile: true
        }
      }
    )
  end

  def setup_plan(*steps)
    Plywo::Subject::SetupPlan.new(framework: "rails", steps:)
  end
end
