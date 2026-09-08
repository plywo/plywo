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

  test "executes ruby.bundle through the typed Ruby handler" do
    ruby_bootstrap = RecordingRubyBootstrap.new
    executor = Plywo::Subject::BootstrapExecutor.new(ruby_bundle_bootstrap: ruby_bootstrap)
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

  test "rejects a ruby.bundle step that does not match the typed contract" do
    executor = Plywo::Subject::BootstrapExecutor.new(
      ruby_bundle_bootstrap: RecordingRubyBootstrap.new
    )
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

  test "fails closed for JavaScript bootstrap until executor capability exists" do
    executor = Plywo::Subject::BootstrapExecutor.new(
      ruby_bundle_bootstrap: RecordingRubyBootstrap.new
    )
    plan = setup_plan(
      {
        phase: "bootstrap",
        operation: "javascript.dependencies",
        provenance: "detected",
        details: {
          manager: "pnpm",
          manifest: "package.json",
          lockfile: "pnpm-lock.yaml",
          frozen_lockfile: true
        }
      }
    )

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: plan)
    end

    assert_match(/does not provide a JavaScript runtime\/package-manager capability yet/, error.message)
  end

  test "never interprets an unknown operation as a command" do
    ruby_bootstrap = RecordingRubyBootstrap.new
    executor = Plywo::Subject::BootstrapExecutor.new(ruby_bundle_bootstrap: ruby_bootstrap)
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
    executor = Plywo::Subject::BootstrapExecutor.new(
      ruby_bundle_bootstrap: RecordingRubyBootstrap.new
    )

    error = assert_raises(Plywo::Subject::BootstrapExecutor::Error) do
      executor.call(root: Pathname("/tmp/customer"), setup_plan: nil)
    end

    assert_equal "Subject setup plan is required for bootstrap execution", error.message
  end

  private

  def setup_plan(*steps)
    Plywo::Subject::SetupPlan.new(framework: "rails", steps:)
  end
end
