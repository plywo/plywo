require "test_helper"
require "tmpdir"

class PlywoSubjectSetupPlanCompilerTest < ActiveSupport::TestCase
  Configuration = Data.define(:persistence, :services)

  class Detector
    def initialize(plan: nil)
      @plan = plan
    end

    def call(root:, configuration:)
      @plan
    end
  end

  test "returns the single detected setup plan" do
    plan = setup_plan("rails")
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan:) ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      assert_same plan, compiler.call(
        root: Pathname(directory),
        configuration: configuration
      )
    end
  end

  test "compiles explicit process services into typed lifecycle operations" do
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan: setup_plan("rails")) ]
    )
    service = Plywo::Subject::Configuration::Service.new(
      name: "mock-api",
      type: "process",
      command: [ "ruby", "script/mock_api.rb" ].freeze,
      port_env: "MOCK_API_PORT",
      url_env: "MOCK_API_URL",
      readiness: Plywo::Subject::Configuration::Readiness.new(
        type: "http",
        path: "/health",
        timeout_seconds: 4
      )
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      compiled = compiler.call(
        root: Pathname(directory),
        configuration: configuration(services: [ service ])
      )

      assert_equal [ "process.start" ], compiled.steps_for("start_services").map(&:operation)
      assert_equal [ "http.wait_ready" ], compiled.steps_for("healthcheck").map(&:operation)
      assert_equal [ "process.stop" ], compiled.steps_for("stop_services").map(&:operation)
      assert_equal [ "mock-api" ], compiled.evidence.fetch("explicit_services")

      start = compiled.steps_for("start_services").fetch(0)
      assert_equal "explicit", start.provenance
      assert_equal [ "ruby", "script/mock_api.rb" ], start.details.fetch("command")
      assert_equal "MOCK_API_PORT", start.details.fetch("port_env")
      assert_equal "MOCK_API_URL", start.details.fetch("url_env")

      readiness = compiled.steps_for("healthcheck").fetch(0)
      assert_equal "/health", readiness.details.fetch("path")
      assert_equal 4, readiness.details.fetch("timeout_seconds")
    end
  end

  test "records declared executor runtime capabilities in plan evidence" do
    plan = Plywo::Subject::SetupPlan.new(
      framework: "rails",
      steps: [],
      evidence: { "framework" => "rails" }
    )
    capabilities = Plywo::Subject::RuntimeCapabilities.new(
      runtimes: { ruby: "3.4.10", node: "24.0.0" },
      package_managers: { pnpm: "10.0.0" }
    )
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan:) ],
      runtime_capabilities: capabilities
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      compiled = compiler.call(
        root: Pathname(directory),
        configuration: configuration
      )

      assert_equal "rails", compiled.evidence.fetch("framework")
      assert_equal capabilities.to_h, compiled.evidence.fetch("executor_runtime_capabilities")
      refute_same plan, compiled
    end
  end

  test "fails closed when no detector can compile the subject" do
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      error = assert_raises(Plywo::Subject::SetupPlanCompiler::Error) do
        compiler.call(
          root: Pathname(directory),
          configuration: configuration
        )
      end

      assert_includes error.message, "Could not compile a subject setup plan"
    end
  end

  test "fails closed when multiple detectors claim the subject" do
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan: setup_plan("rails")), Detector.new(plan: setup_plan("other")) ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      error = assert_raises(Plywo::Subject::SetupPlanCompiler::Error) do
        compiler.call(
          root: Pathname(directory),
          configuration: configuration
        )
      end

      assert_includes error.message, "Ambiguous subject setup plan"
      assert_includes error.message, "other, rails"
    end
  end

  private

  def configuration(services: [])
    Configuration.new(persistence: "auto", services:)
  end

  def setup_plan(framework)
    Plywo::Subject::SetupPlan.new(
      framework:,
      steps: [
        {
          phase: "cleanup",
          operation: "subject.state_cleanup",
          provenance: "executor_default"
        }
      ]
    )
  end
end
